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
  /// Counts calls, so a test can assert "ordered once per pass, not once per
  /// row" (B5). That behaviour is otherwise invisible from outside: both the
  /// old shape and the new one return the same answer, only at different cost.
  /// The same affordance `InsightsCache.missCount` is, for the same reason.
  ///
  /// `nonisolated(unsafe)` because it is written from the pipeline actor and
  /// read from a test, is never read by the app, and a lock here would be
  /// synchronisation added to production code purely to count.
  nonisolated(unsafe) static var orderingCount = 0

  public static func precedenceOrdered(_ rules: [RuleSnapshot]) -> [RuleSnapshot] {
    orderingCount += 1
    return rules.sorted { lhs, rhs in
      if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  /// The literal characters a pattern must start with, or `""` when it starts
  /// with `*` and therefore could match anywhere.
  ///
  /// Uppercased, like the pattern itself: it is compared against
  /// `normalizedDescription`, which `normalizeDescription` has already
  /// uppercased. Used only to *narrow* a fetch - `globMatches` remains the
  /// authority on whether a row actually matches.
  public static func literalPrefix(of pattern: String) -> String {
    String(pattern.uppercased().prefix { $0 != "*" })
  }

  /// First match wins and evaluation stops - exactly one category, never two.
  /// Disabled rules never match.
  ///
  /// **`rules` must already be `precedenceOrdered`.** It used to sort here, on
  /// every call, which meant twice per transaction on ingest and twice per row
  /// on a reapply over the whole ledger. The order is a property of the rule
  /// set, not of the row being tested, so it is computed once per pass by the
  /// caller. Passing an unordered array is not a crash, it is silently wrong
  /// precedence - which is why every caller in the repo is in this unit.
  ///
  /// **Patterns are matched uppercased.** `normalizedDescription` is uppercased
  /// by `normalizeDescription`, `globMatches` is case-sensitive, and nothing
  /// uppercases what the user typed - so a rule typed as `*swiggy*` matched
  /// nothing, ever, with no error and no empty-preview warning to say so.
  public static func firstMatch(
    normalizedDescription: String,
    in orderedRules: [RuleSnapshot]
  ) -> RuleSnapshot? {
    orderedRules.first { rule in
      rule.isEnabled
        && globMatches(pattern: rule.pattern.uppercased(), value: normalizedDescription)
    }
  }

  /// On ingest, and on the retroactive pass: apply to any row whose category
  /// is not `.manual`. Returns `nil` when nothing changed.
  ///
  /// A row that matches nothing keeps whatever category it has. Clearing a
  /// stale `.rule` assignment would be a second, unrequested behaviour, and
  /// it is the same "helpfully recategorizing" mistake the delete path calls
  /// out by name.
  /// `orderedRules` must already be `precedenceOrdered` - see `firstMatch`.
  public static func apply(
    _ orderedRules: [RuleSnapshot],
    to row: TransactionSnapshot
  ) -> TransactionSnapshot? {
    guard row.categorySource != .manual else { return nil }
    guard
      let match = firstMatch(normalizedDescription: row.normalizedDescription, in: orderedRules)
    else {
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
