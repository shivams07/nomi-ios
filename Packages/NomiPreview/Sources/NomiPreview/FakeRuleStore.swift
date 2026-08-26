import Foundation
import NomiCore
import SwiftData

@MainActor
public final class FakeRuleStore: RuleStore {
  public var rules: [Rule]
  private let matchPool: [String]

  public init(rules: [Rule] = PreviewData.rules, matchPool: [String] = PreviewData.transactions.map(\.normalizedDescription)) {
    self.rules = rules
    self.matchPool = matchPool
  }

  @discardableResult
  public func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    InMemoryModelContainer.warmUp()
    let rule = Rule(pattern: pattern, categoryID: categoryID, priority: rules.count)
    InMemoryModelContainer.inserted(rule)
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
