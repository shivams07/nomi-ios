import Foundation

/// One category crossing its budget threshold, once, in one period.
///
/// Produced by `BudgetAlertEvaluator` and nothing else. It is a value: it holds
/// no store reference and reading it triggers no work.
///
/// `wasSuppressed` is the difference between "show this" and "record that it
/// happened so it never shows". See design §2.2 — turning alerts on mid-month
/// must not retroactively fire six notifications, but it must still close the
/// door on the rest of that month.
public struct BudgetAlert: Sendable, Hashable, Identifiable {
  public let categoryID: UUID
  public let categoryName: String
  /// "YYYY-MM", taken verbatim from `BudgetProgress.periodKey`. Never re-derived
  /// here — a second month-boundary calculation is exactly the disagreement
  /// §2.2 forbids.
  public let periodKey: String
  public let budgetMinor: Int
  public let spentMinor: Int
  /// Unclamped, as supplied by `InsightsStore`. `> 1` means over budget.
  public let fraction: Double
  /// `true` => log it, never present it.
  public let wasSuppressed: Bool

  public var id: String { logKey }

  /// The `(categoryID, periodKey)` identity of the `BudgetAlertLog` row that
  /// makes this alert un-repeatable for the rest of the period.
  public var logKey: String {
    BudgetAlertEvaluator.logKey(categoryID: categoryID, periodKey: periodKey)
  }

  public init(
    categoryID: UUID,
    categoryName: String,
    periodKey: String,
    budgetMinor: Int,
    spentMinor: Int,
    fraction: Double,
    wasSuppressed: Bool
  ) {
    self.categoryID = categoryID
    self.categoryName = categoryName
    self.periodKey = periodKey
    self.budgetMinor = budgetMinor
    self.spentMinor = spentMinor
    self.fraction = fraction
    self.wasSuppressed = wasSuppressed
  }
}

/// Why the evaluator was asked. The arithmetic is identical either way; only the
/// disposition of the result changes.
public enum BudgetAlertTrigger: String, Sendable, Codable, CaseIterable {
  /// A commit batch landed. Crossings fire.
  case postCommit
  /// The user just turned budget alerts on. Crossings are logged suppressed and
  /// nothing is shown (§2.2).
  case alertsEnabled
}
