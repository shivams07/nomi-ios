import Foundation

/// Decides which budget alerts are due. **Pure.**
///
/// No `ModelContext`, no persistence, no I/O, no store access — same shape as
/// `FileImportService`, which produces drafts and never writes (design §2.2).
///
/// It does **not** compute progress. `InsightsStore.budgetProgress(year:month:)`
/// is the one owner of that arithmetic; a second implementation here is how a
/// progress bar and a notification end up disagreeing.
///
/// The caller supplies `firedKeys` — the `logKey` of every `BudgetAlertLog` row
/// that already exists — and persists a row for every alert returned. That row,
/// not an in-memory flag, is what makes "once per category per month" hold
/// across the app being killed between transactions.
public struct BudgetAlertEvaluator: Sendable {
  public init() {}

  /// `(categoryID, periodKey)`, the identity of a `BudgetAlertLog` row.
  ///
  /// The single place this string is built. U8 must derive `firedKeys` by
  /// calling this with each stored row's `categoryID` and `periodKey` — if it
  /// formats the key itself the two will drift and every alert fires twice.
  public static func logKey(categoryID: UUID, periodKey: String) -> String {
    "\(categoryID.uuidString)|\(periodKey)"
  }

  /// - Parameters:
  ///   - progress: current progress for every budgeted category, from
  ///     `InsightsStore`. Rows for other periods are handled correctly — the
  ///     key carries the period — but callers normally pass one period.
  ///   - firedKeys: `logKey` of every existing `BudgetAlertLog` row, fired or
  ///     suppressed. A suppressed row silences the rest of that period exactly
  ///     as a fired one does; that is the whole point of writing it.
  ///   - settings: the user's current settings. `budgetAlertsEnabled == false`
  ///     yields nothing, whatever the progress and whatever the trigger.
  ///   - trigger: `.postCommit` fires; `.alertsEnabled` returns the same
  ///     crossings marked `wasSuppressed` so the caller logs them and shows
  ///     nothing.
  /// - Returns: one alert per newly-crossed category, ordered by descending
  ///   `fraction` then category name, so the order is deterministic rather than
  ///   whatever order the store happened to fetch in.
  public func evaluate(
    _ progress: [BudgetProgress],
    firedKeys: Set<String>,
    settings: NotificationSettings,
    trigger: BudgetAlertTrigger = .postCommit
  ) -> [BudgetAlert] {
    guard settings.budgetAlertsEnabled else { return [] }

    let suppressed = (trigger == .alertsEnabled)

    return progress
      .filter { hasCrossed($0, threshold: settings.thresholdFraction) }
      .filter { !firedKeys.contains(Self.logKey(categoryID: $0.id, periodKey: $0.periodKey)) }
      .sorted { lhs, rhs in
        if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
        return lhs.categoryName < rhs.categoryName
      }
      .map {
        BudgetAlert(
          categoryID: $0.id,
          categoryName: $0.categoryName,
          periodKey: $0.periodKey,
          budgetMinor: $0.budgetMinor,
          spentMinor: $0.spentMinor,
          fraction: $0.fraction,
          wasSuppressed: suppressed
        )
      }
  }

  /// `>=`, so the spec's "90%" fires at exactly 90% rather than a paisa past it.
  ///
  /// `fraction` is trusted as given. The two guards are not defensive noise:
  /// `setBudget(amountMinor: 0)` means *remove*, and a zero denominator reaching
  /// here as `.infinity` would satisfy any threshold and fire an alert for a
  /// budget the user deleted.
  private func hasCrossed(_ progress: BudgetProgress, threshold: Double) -> Bool {
    guard progress.budgetMinor > 0, progress.fraction.isFinite else { return false }
    return progress.fraction >= threshold
  }
}
