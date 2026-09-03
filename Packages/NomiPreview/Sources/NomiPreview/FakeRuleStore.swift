import Foundation
import NomiCore

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

  public func delete(_ id: UUID) throws {
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
