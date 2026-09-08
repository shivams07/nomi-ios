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
  private let matchPool: [String]

  public init(rules: [Rule] = PreviewData.rules, matchPool: [String] = PreviewData.transactions.map(\.normalizedDescription)) {
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
  public func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    let rule = Rule(
      pattern: pattern,
      categoryID: categoryID,
      priority: (rules.map(\.priority).min() ?? 1) - 1
    )
    rules.append(rule)
    let matched = matchPool.filter { globMatches(pattern: pattern, value: $0) }.count
    return RuleApplyResult(matched: matched, recategorized: matched)
  }

  @discardableResult
  public func update(_ id: UUID, pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    guard let rule = rules.first(where: { $0.id == id }) else {
      return RuleApplyResult(matched: 0, recategorized: 0)
    }
    rule.pattern = pattern
    rule.categoryID = categoryID
    let matched = matchPool.filter { globMatches(pattern: pattern, value: $0) }.count
    return RuleApplyResult(matched: matched, recategorized: matched)
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

  public func preview(pattern: String) throws -> Int {
    matchPool.filter { globMatches(pattern: pattern, value: $0) }.count
  }
}
