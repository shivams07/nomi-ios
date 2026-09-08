import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The error `delete` throws for a rule the seed owns.
///
/// Deliberately not a case on `AppStoreError`: that type is declared in
/// `SwiftDataCategoryStore.swift`, a file this unit does not own, and the two
/// stores have no reason to share an error namespace beyond the coincidence
/// that each has a system row. The *shape* is copied on purpose —
/// `AppStoreError.systemCategoryCannotBeDeleted` is the precedent, down to the
/// backstop-rather-than-the-path role.
public enum RuleStoreError: Error, Sendable, Equatable {
  /// A seeded rule. `RulesScreen` disables deletion for a system row and says
  /// so in its own copy, so reaching this throw means something bypassed the
  /// list — it is the store-side backstop, not the user-facing path.
  case systemRuleCannotBeDeleted
}

/// The real `RuleStore`.
///
/// `create` and `update` are retroactive — the design's "on create or edit,
/// re-apply across the whole ledger where `categorySource != .manual`", which is
/// what makes a new rule tidy up history without a re-import — and they must
/// return the counts synchronously, because `RuleEditorSheet` shows them. A
/// `@MainActor` protocol method that returns a value cannot await, so the pass
/// is driven here rather than handed to the ingest pipeline.
///
/// **The pass is driven here, but the semantics are not reimplemented.** Every
/// decision goes through `RuleEngine` — the same public type, the same
/// `firstMatch` / `apply` calls, in the same order the ingest pass makes them.
/// What is duplicated is the loop; what would have been dangerous to duplicate,
/// precedence and provenance, is shared.
///
/// The residual is a race, not a divergence: a mail sync committing through the
/// pipeline's context while this pass runs on the main context can have one row
/// written twice, last writer winning. The next rule edit corrects it, and
/// neither ordering produces a wrong *category* — only a briefly stale one.
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

  /// Deleting a rule re-evaluates nothing. `appliedRuleID` is cleared where it
  /// pointed at this rule; `categoryID` and `categorySource` are left exactly
  /// as they are.
  ///
  /// That looks like an omission and is the opposite: a row categorised by a
  /// rule the user has now deleted should keep its category. Re-running the
  /// remaining rules over it would silently move spend between categories as a
  /// side effect of tidying a rule list.
  ///
  /// **A seeded rule cannot be deleted at all.** `DefaultRuleSeed.apply` runs
  /// on every launch and is idempotent by id, so a deleted seed row is
  /// indistinguishable from one that was never seeded and comes straight back
  /// — the delete would appear to work, survive one relaunch, and undo itself.
  /// Refusing is honest where succeeding is not. `setEnabled(_:false)` is the
  /// affordance that actually persists, and it is what the list offers instead.
  public func delete(_ id: UUID) throws {
    guard let rule = try rule(id: id) else { return }
    guard !rule.isSystem else { throw RuleStoreError.systemRuleCannotBeDeleted }

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

  /// Turn a rule off, or back on. No reapply, deliberately.
  ///
  /// `RuleEngine.firstMatch` skips a rule whose `isEnabled` is false, and
  /// `ruleSnapshots()` does not even fetch one, so disabling takes effect on
  /// the next pass — the next import, the next manual entry, the next rule
  /// edit. What it does *not* do is revisit rows this rule already categorised.
  ///
  /// That is the same policy `delete` holds to, and for the same reason: a row
  /// filed under Groceries should not silently move because the user switched
  /// a rule off to stop it firing on *future* rows. Re-running the remaining
  /// rules would move spend between categories as a side effect of a toggle,
  /// which is the behaviour `delete`'s note above calls out by name.
  ///
  /// It still `didWrite()`s. Nothing about the ledger changed, but the rule
  /// list did, and `RulesScreen` renders `isEnabled` — without it the toggle
  /// would not visibly move on a store the screen observes through the
  /// coordinator.
  public func setEnabled(_ id: UUID, _ enabled: Bool) throws {
    guard let rule = try rule(id: id) else { return }

    rule.isEnabled = enabled
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
  /// `globMatches` is a glob and cannot itself be a `#Predicate`, so SQLite
  /// cannot answer this question - but it can answer a *narrower* one. A
  /// pattern with a literal prefix (`UPI/PM*`) can only match rows whose
  /// description contains that prefix, so the fetch is filtered on it and only
  /// candidate rows are materialised. `globMatches` still decides.
  ///
  /// `contains` rather than a starts-with: it is a strict superset of the rows
  /// a prefix match could return, so it cannot lose a match, and it does not
  /// depend on which `String` operations SwiftData can translate to SQL. A
  /// pattern beginning with `*` has no literal prefix and still costs a full
  /// scan - unavoidable, and the case a preview is least likely to be run on
  /// mid-typing.
  ///
  /// The pattern is uppercased first: `normalizedDescription` is uppercase, so
  /// a lowercase pattern previewed as zero and then matched nothing forever.
  public func preview(pattern: String) throws -> Int {
    let uppercased = pattern.uppercased()
    return try candidateRows(matching: uppercased, includeManual: true)
      .filter { globMatches(pattern: uppercased, value: $0.normalizedDescription) }
      .count
  }

  // MARK: -

  /// Every rule edit re-ran this, and it began by materialising every
  /// non-manual row in the ledger as a `@Model` instance - synchronously, on
  /// the main actor, with the user's finger still on the Save button.
  ///
  /// Now: the rule set is ordered once rather than once per row, and the fetch
  /// is narrowed to rows that could match *some* enabled rule, one fetch per
  /// distinct literal prefix, unioned by id. A rule whose pattern starts with
  /// `*` has no prefix and forces the full scan for the whole pass, which is
  /// correct rather than clever - if one rule can match anywhere, every row is
  /// a candidate.
  ///
  /// Narrowing is safe because a row matching no rule is left untouched today:
  /// the loop's first `guard` skips it. Rows excluded by the fetch are exactly
  /// rows that guard would have skipped.
  private func reapply() throws -> RuleApplyResult {
    let rules = RuleEngine.precedenceOrdered(try ruleSnapshots())
    let rows = try candidateRows(forAnyOf: rules)
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

  /// Rows that could match `pattern`, materialising as few as possible.
  private func candidateRows(matching pattern: String, includeManual: Bool) throws -> [Transaction] {
    let prefix = RuleEngine.literalPrefix(of: pattern)
    let manual = CategorySource.manual.rawValue

    if prefix.isEmpty {
      guard !includeManual else { return try context.fetch(FetchDescriptor<Transaction>()) }
      return try context.fetch(
        FetchDescriptor<Transaction>(
          predicate: #Predicate<Transaction> { $0.categorySourceRaw != manual }))
    }

    if includeManual {
      return try context.fetch(
        FetchDescriptor<Transaction>(
          predicate: #Predicate<Transaction> { $0.normalizedDescription.contains(prefix) }))
    }
    return try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.categorySourceRaw != manual && $0.normalizedDescription.contains(prefix)
        }))
  }

  /// The union of `candidateRows(matching:)` over every enabled rule, keyed by
  /// id so a row matching two prefixes is materialised once.
  private func candidateRows(forAnyOf rules: [RuleSnapshot]) throws -> [Transaction] {
    let prefixes = Set(rules.filter(\.isEnabled).map { RuleEngine.literalPrefix(of: $0.pattern) })
    let manual = CategorySource.manual.rawValue

    guard !prefixes.isEmpty else { return [] }
    guard !prefixes.contains("") else {
      return try context.fetch(
        FetchDescriptor<Transaction>(
          predicate: #Predicate<Transaction> { $0.categorySourceRaw != manual }))
    }

    var byID: [UUID: Transaction] = [:]
    for prefix in prefixes {
      for row in try context.fetch(
        FetchDescriptor<Transaction>(
          predicate: #Predicate<Transaction> {
            $0.categorySourceRaw != manual && $0.normalizedDescription.contains(prefix)
          }))
      {
        byID[row.id] = row
      }
    }
    return Array(byID.values)
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
