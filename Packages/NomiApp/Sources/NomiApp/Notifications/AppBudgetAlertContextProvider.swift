import Foundation
import NomiCore
import SwiftData

/// The seam U10 declared and left for U8: it reads budget progress, turns
/// stored `BudgetAlertLog` rows into `firedKeys`, and persists a row per alert.
///
/// **`firedKeys` are built with `BudgetAlertEvaluator.logKey`, never formatted
/// here.** That function's own doc comment says why: "if it formats the key
/// itself the two will drift and every alert fires twice."
///
/// Likewise the period key on the log row is `BudgetProgress.periodKey`,
/// carried through verbatim from `InsightsStore` (§2.2: "Never re-derived here
/// — a second month-boundary calculation is exactly the disagreement §2.2
/// forbids"). The only place this type derives a month at all is choosing
/// *which* month to ask about, and it asks `InsightsStore`, which asks
/// `dateRange(for:)`.
public final class AppBudgetAlertContextProvider: BudgetAlertContextProviding, @unchecked Sendable {
  private let insightsStore: any InsightsStore
  private let settingsStore: NotificationSettingsStore
  private let context: ModelContext
  private let calendar: Calendar
  private let now: @Sendable () -> Date

  @MainActor
  public init(
    insightsStore: any InsightsStore,
    settingsStore: NotificationSettingsStore,
    context: ModelContext,
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.insightsStore = insightsStore
    self.settingsStore = settingsStore
    self.context = context
    self.calendar = calendar
    self.now = now
  }

  public func currentContext() async -> BudgetAlertContext {
    await MainActor.run { () -> BudgetAlertContext in
      let components = calendar.dateComponents([.year, .month], from: now())
      guard let year = components.year, let month = components.month else {
        return BudgetAlertContext(progress: [], firedKeys: [], settings: settingsStore.settings)
      }

      let progress = (try? insightsStore.budgetProgress(year: year, month: month)) ?? []
      let periodKey = InsightsAggregator.periodKey(year: year, month: month)

      return BudgetAlertContext(
        progress: progress,
        firedKeys: firedKeys(periodKey: periodKey),
        settings: settingsStore.settings
      )
    }
  }

  public func recordFired(_ alerts: [BudgetAlert]) async {
    await MainActor.run {
      for alert in alerts {
        context.insert(
          BudgetAlertLog(
            categoryID: alert.categoryID,
            periodKey: alert.periodKey,
            firedAt: now(),
            wasSuppressed: alert.wasSuppressed
          )
        )
      }
      // A failed save here means the alert is not recorded, so it will be
      // re-evaluated on the next commit and may fire again. That is the
      // failure `BudgetAlertObserver`'s record-then-schedule ordering chose:
      // a repeated notification, not a lost one.
      try? context.save()
    }
  }

  /// §2.2's opt-in rule, and the one non-obvious line in the whole feature:
  ///
  /// > On enable, U8 evaluates current progress and writes a `BudgetAlertLog`
  /// > row with `wasSuppressed = true` for every category already over
  /// > threshold, firing nothing.
  ///
  /// It calls the evaluator directly rather than `BudgetAlertObserver.didCommit`
  /// — the opposite of what `BudgetStore.setBudget` must do — because
  /// `didCommit` hardcodes `.postCommit`, and `.alertsEnabled` is the whole
  /// point of this call. There is no path through the observer that produces a
  /// suppressed alert.
  public func suppressCurrentCrossings(evaluator: BudgetAlertEvaluator = BudgetAlertEvaluator()) async {
    let snapshot = await currentContext()
    let suppressed = evaluator.evaluate(
      snapshot.progress,
      firedKeys: snapshot.firedKeys,
      settings: snapshot.settings,
      trigger: .alertsEnabled
    )
    guard !suppressed.isEmpty else { return }
    await recordFired(suppressed)
    // Nothing is scheduled. `BudgetNotificationScheduler.schedule` throws on a
    // suppressed alert rather than dropping it, so a future refactor that
    // wires this to the scheduler fails loudly instead of quietly opting the
    // user into six notifications.
  }

  @MainActor
  private func firedKeys(periodKey: String) -> Set<String> {
    let descriptor = FetchDescriptor<BudgetAlertLog>(
      predicate: #Predicate<BudgetAlertLog> { $0.periodKey == periodKey }
    )
    let rows = (try? context.fetch(descriptor)) ?? []
    return Set(
      rows.map { BudgetAlertEvaluator.logKey(categoryID: $0.categoryID, periodKey: $0.periodKey) }
    )
  }
}
