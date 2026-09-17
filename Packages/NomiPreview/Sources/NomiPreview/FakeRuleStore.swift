import Foundation
import NomiCore

/// What this fake throws for a system rule.
///
/// `RuleStore.delete`'s contract is that it throws, not *which* error it
/// throws: the real case is `RuleStoreError.systemRuleCannotBeDeleted` in
/// `NomiApp`, and `NomiPreview` sits below `NomiApp` in the package graph and
/// cannot name it. Two types, one contract — which is fine only because no
/// caller branches on the case. If one ever needs to, the error belongs in
/// `NomiCore` next to the protocol and both conformers should throw it.
public enum FakeRuleStoreError: Error, Sendable, Equatable {
  case systemRuleCannotBeDeleted
}

@MainActor
public final class FakeRuleStore: RuleStore {
  public var rules: [Rule]

  /// Whole rows, not descriptions.
  ///
  /// It held `[String]` until §W2-5, which was enough to count a pattern and
  /// is not enough to count a *scope* — direction, account and amount are not
  /// in a description. A fake that ignored the scope would put a match count in
  /// front of the user that the real store contradicts, which is the same
  /// failure the front-insertion note below is about, in a third place.
  private let matchPool: [Transaction]

  public init(rules: [Rule] = PreviewData.rules, matchPool: [Transaction] = PreviewData.transactions) {
    self.rules = rules
    self.matchPool = matchPool
  }

  /// Front-insertion, matching `SwiftDataRuleStore.create` — see the long note
  /// there for why the back of the list is wrong and why a reserved band does
  /// not work either.
  ///
  /// `priority: rules.count` was the same bug in a different spelling. It has to
  /// move with the real store or every preview and every screen built against
  /// this one demonstrates the behaviour that was just fixed, which is worse
  /// than having no fake at all.
  @discardableResult
  public func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    let rule = Rule(
      pattern: pattern,
      categoryID: categoryID,
      priority: (rules.map(\.priority).min() ?? 1) - 1,
      scope: scope
    )
    rules.append(rule)
    let matched = count(pattern: pattern, scope: scope)
    return RuleApplyResult(matched: matched, recategorized: matched)
  }

  @discardableResult
  public func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
    guard let rule = rules.first(where: { $0.id == id }) else {
      return RuleApplyResult(matched: 0, recategorized: 0)
    }
    rule.pattern = pattern
    rule.categoryID = categoryID
    rule.scope = scope
    let matched = count(pattern: pattern, scope: scope)
    return RuleApplyResult(matched: matched, recategorized: matched)
  }

  /// Mirrors `SwiftDataRuleStore.setScope`: the scope moves and the counts are
  /// dropped. The real one re-applies across the ledger; there is no ledger
  /// here to re-apply to.
  public func setScope(_ id: UUID, _ scope: RuleScope) throws {
    guard let rule = rules.first(where: { $0.id == id }) else { return }
    rule.scope = scope
  }

  /// Mirrors `SwiftDataRuleStore.setEnabled`: flips the flag and stops there.
  ///
  /// No recount of `matchPool`, because the real store does not re-apply
  /// either — disabling changes what the *next* pass does and leaves rows that
  /// are already categorised alone. A fake that returned a fresh count here
  /// would have every preview demonstrate a behaviour production does not have.
  public func setEnabled(_ id: UUID, _ enabled: Bool) throws {
    guard let rule = rules.first(where: { $0.id == id }) else { return }
    rule.isEnabled = enabled
  }

  /// Refuses a system rule, like the real store.
  ///
  /// A fake that quietly deleted one would let `RulesScreen`'s previews show a
  /// swipe-to-delete that production rejects — the failure mode the front-
  /// insertion note above already describes, in a second place.
  public func delete(_ id: UUID) throws {
    guard let rule = rules.first(where: { $0.id == id }) else { return }
    guard !rule.isSystem else { throw FakeRuleStoreError.systemRuleCannotBeDeleted }
    rules.removeAll { $0.id == id }
  }

  public func reorder(_ orderedIDs: [UUID]) throws {
    var byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    for (index, id) in orderedIDs.enumerated() {
      byID[id]?.priority = index
    }
    rules.sort { $0.priority < $1.priority }
  }

  public func preview(pattern: String, scope: RuleScope) throws -> Int {
    count(pattern: pattern, scope: scope)
  }

  /// Scope first, then the glob — the order `RuleEngine.firstMatch` uses, so
  /// the two cannot drift on which condition wins.
  ///
  /// The pattern is **not** uppercased here, unlike the real store: this pool
  /// is preview data matched against patterns written in the same previews,
  /// and uppercasing one side only would change every existing count. The
  /// place that discrepancy is pinned is `RulePriorityTests`, which asserts
  /// the real store's case handling directly.
  private func count(pattern: String, scope: RuleScope) -> Int {
    matchPool.filter { row in
      scope.admits(direction: row.direction, accountID: row.accountID, amountMinor: row.amountMinor)
        && globMatches(pattern: pattern, value: row.normalizedDescription)
    }.count
  }
}
