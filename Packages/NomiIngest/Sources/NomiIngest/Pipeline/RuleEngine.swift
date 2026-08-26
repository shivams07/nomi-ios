import Foundation
import NomiCore

/// Rule precedence and the three rule-lifecycle passes. Pure — every function
/// here takes snapshots and returns snapshots.
public enum RuleEngine {

  /// Ascending `priority`, ties broken by ascending `createdAt` (older wins).
  ///
  /// The design stops there, which leaves two rules created in the same
  /// millisecond at the same priority ordered by whatever the fetch returned.
  /// `id.uuidString` is the final tiebreak: arbitrary, but stable across
  /// devices and across fetches, which is what "deterministic" has to mean
  /// when the store is CloudKit-backed.
  public static func precedenceOrdered(_ rules: [RuleSnapshot]) -> [RuleSnapshot] {
    rules.sorted { lhs, rhs in
      if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// First match wins and evaluation stops — exactly one category, never two.
  /// Disabled rules never match.
  public static func firstMatch(
    normalizedDescription: String,
    in rules: [RuleSnapshot]
  ) -> RuleSnapshot? {
    precedenceOrdered(rules).first { rule in
      rule.isEnabled && globMatches(pattern: rule.pattern, value: normalizedDescription)
    }
  }

  /// On ingest, and on the retroactive pass: apply to any row whose category
  /// is not `.manual`. Returns `nil` when nothing changed.
  ///
  /// A row that matches nothing keeps whatever category it has. Clearing a
  /// stale `.rule` assignment would be a second, unrequested behaviour, and
  /// it is the same "helpfully recategorizing" mistake the delete path calls
  /// out by name.
  public static func apply(
    _ rules: [RuleSnapshot],
    to row: TransactionSnapshot
  ) -> TransactionSnapshot? {
    guard row.categorySource != .manual else { return nil }
    guard let match = firstMatch(normalizedDescription: row.normalizedDescription, in: rules) else {
      return nil
    }

    var updated = row
    updated.categoryID = match.categoryID
    updated.categorySourceRaw = CategorySource.rule.rawValue
    updated.appliedRuleID = match.id
    return updated == row ? nil : updated
  }

  /// Rule delete. No re-evaluation at all: `appliedRuleID` is nulled where it
  /// pointed at the deleted rule, `categoryID` and `categorySource` are
  /// untouched. User story 7.
  public static func clearingProvenance(
    of ruleID: UUID,
    from row: TransactionSnapshot
  ) -> TransactionSnapshot? {
    guard row.appliedRuleID == ruleID else { return nil }
    var updated = row
    updated.appliedRuleID = nil
    return updated
  }
}
