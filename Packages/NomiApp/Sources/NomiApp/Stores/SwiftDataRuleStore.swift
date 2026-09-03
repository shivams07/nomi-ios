import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The real `RuleStore`.
///
/// `create` and `update` are retroactive — the design's "on create or edit,
/// re-apply across the whole ledger where `categorySource != .manual`", which is
/// what makes a new rule tidy up history without a re-import — and they must
/// return the counts synchronously, because `RuleEditorSheet` shows them.
/// `IngestPipeline.reapplyRules()` does exactly this pass and is `async`, so it
/// cannot be reached from a `@MainActor` protocol method that returns a value.
///
/// **The pass is therefore driven here, but the semantics are not
/// reimplemented.** Every decision goes through `RuleEngine` — the same public
/// type, the same `firstMatch` / `apply` calls, in the same order the pipeline
/// makes them. What is duplicated is the loop; what would have been dangerous to
/// duplicate, precedence and provenance, is shared.
///
/// The residual is a race, not a divergence: a mail sync committing through the
/// pipeline's context while this pass runs on the main context can have one row
/// written twice, last writer winning. The next rule edit or `reapplyRules()`
/// corrects it, and neither ordering produces a wrong *category* — only a
/// briefly stale one.
@MainActor
public final class SwiftDataRuleStore: RuleStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let now: () -> Date

  public init(context: ModelContext, coordinator: WriteCoordinator, now: @escaping () -> Date = { Date() }) {
    self.context = context
    self.coordinator = coordinator
    self.now = now
  }

  /// **A new rule goes to the FRONT of precedence, not the back.**
  ///
  /// `RuleEngine.precedenceOrdered` sorts ascending and `firstMatch` stops at
  /// the first hit, so lower `priority` wins. This used to assign
  /// `max() + 1`, which put every rule the user wrote *last* — losing to
  /// everything already in the store.
  ///
  /// That was invisible while a fresh install had no rules at all. Once
  /// `DefaultRuleSeed` shipped 47 of them, the very first rule a user wrote lost
  /// to all 47, and there was nothing on screen to explain why.
  ///
  /// **Why not a reserved priority band for the seed.** Giving seeded rules a
  /// high band and user rules a low one looks equivalent and is not: `reorder`
  /// below rewrites `priority` to the array index across *every* rule, so a
  /// single drag-to-reorder gesture flattens the band and the bug returns with
  /// nothing to show for it. Front-insertion is defined relative to whatever
  /// `reorder` last wrote, so it cannot be collapsed that way.
  ///
  /// `?? 1` rather than `?? 0` so the first rule in an empty store lands on 0
  /// rather than -1 — cosmetic, but it keeps a fresh install's rule list reading
  /// 0, -1, -2 instead of -1, -2, -3.
  ///
  /// One consequence worth naming: this reverses precedence *between* two user
  /// rules. The newest now wins where the oldest used to. That is the behaviour
  /// the + button implies — a rule you just wrote should take effect — and
  /// `RulesScreen` sorts by `priority`, so the new rule also appears at the top
  /// of the list where the user is looking. Drag-to-reorder overrides both.
  @discardableResult
  public func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    let existing = try context.fetch(FetchDescriptor<Rule>())
    let rule = Rule(
      pattern: pattern,
      categoryID: categoryID,
      priority: (existing.map(\.priority).min() ?? 1) - 1
    )
    context.insert(rule)
    try context.save()
    return try reapply()
  }

  @discardableResult
  public func update(_ id: UUID, pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    guard let rule = try rule(id: id) else { return RuleApplyResult(matched: 0, recategorized: 0) }
    rule.pattern = pattern
    rule.categoryID = categoryID
    try context.save()
    return try reapply()
  }

  /// Deleting a rule re-evaluates nothing — `IngestPipeline.ruleDeleted`'s rule,
  /// held to here. `appliedRuleID` is cleared where it pointed at this rule;
  /// `categoryID` and `categorySource` are left exactly as they are.
  ///
  /// That looks like an omission and is the opposite: a row categorised by a
  /// rule the user has now deleted should keep its category. Re-running the
  /// remaining rules over it would silently move spend between categories as a
  /// side effect of tidying a rule list.
  public func delete(_ id: UUID) throws {
    guard let rule = try rule(id: id) else { return }
    let target: UUID? = id
    let timestamp = now()

    for row in try context.fetch(
      FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.appliedRuleID == target })
    ) {
      row.appliedRuleID = nil
      row.updatedAt = timestamp
    }

    context.delete(rule)
    try context.save()
    coordinator.didWrite()
  }

  /// Priority is the array index. Rewritten wholesale rather than swapped,
  /// because a drag can move any row to any position and a partial rewrite
  /// leaves gaps that make the next reorder's arithmetic wrong.
  public func reorder(_ orderedIDs: [UUID]) throws {
    let rules = try context.fetch(FetchDescriptor<Rule>())
    let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for (index, id) in orderedIDs.enumerated() {
      byID[id]?.priority = index
    }
    try context.save()
    // Precedence changed, so which rule wins on an overlapping pattern changed.
    // Existing rows are not re-evaluated — same reasoning as `delete`.
    coordinator.didWrite()
  }

  /// How many rows this pattern would match, for the live count in the editor.
  ///
  /// Counts the whole ledger, not just the rule pass's working set: the user is
  /// asking "what does this pattern hit", and answering with a number that
  /// silently excludes their manually-categorised rows would read as the
  /// pattern being wrong.
  ///
  /// One full scan per keystroke on a large ledger is the cost, and it is real.
  /// It stays because `globMatches` cannot be expressed as a `#Predicate` — it
  /// is a glob, not a `contains` — so there is no version of this that SQLite
  /// can answer.
  public func preview(pattern: String) throws -> Int {
    try context.fetch(FetchDescriptor<Transaction>())
      .filter { globMatches(pattern: pattern, value: $0.normalizedDescription) }
      .count
  }

  // MARK: -

  private func reapply() throws -> RuleApplyResult {
    let rules = try ruleSnapshots()
    let manual = CategorySource.manual.rawValue
    let rows = try context.fetch(
      FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.categorySourceRaw != manual })
    )
    let timestamp = now()

    var matched = 0
    var recategorized = 0
    var affected: Set<UUID> = []

    for row in rows {
      let snapshot = TransactionSnapshot(row)
      guard RuleEngine.firstMatch(normalizedDescription: snapshot.normalizedDescription, in: rules) != nil
      else { continue }
      matched += 1

      guard let next = RuleEngine.apply(rules, to: snapshot) else { continue }
      if next.categoryID != snapshot.categoryID {
        recategorized += 1
        if let previous = snapshot.categoryID { affected.insert(previous) }
        if let current = next.categoryID { affected.insert(current) }
      }
      row.categoryID = next.categoryID
      row.categorySourceRaw = next.categorySourceRaw
      row.appliedRuleID = next.appliedRuleID
      row.updatedAt = timestamp
    }

    try context.save()
    coordinator.didWrite(affectedCategoryIDs: affected)
    return RuleApplyResult(matched: matched, recategorized: recategorized)
  }

  private func rule(id: UUID) throws -> Rule? {
    var descriptor = FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private func ruleSnapshots() throws -> [RuleSnapshot] {
    try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.isEnabled }))
      .map { RuleSnapshot($0) }
  }
}
