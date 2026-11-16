import Foundation
import NomiCore
import Observation

/// The Plan tab's state (S7): this month's budgets, the one suggestion, and the
/// recurring series the store still shows. The screen reads it and calls `load`
/// and `dismiss`; nothing here is view state.
@Observable @MainActor final class PlanModel {
  /// Whether the recurring read has a store to read, and whether it worked.
  enum RecurringState: Equatable {
    case unavailable
    case loaded
    case failed
  }

  @ObservationIgnored let insightsStore: InsightsStore
  @ObservationIgnored let recurringStore: (any RecurringInsightsStore)?
  @ObservationIgnored let calendar: Calendar
  @ObservationIgnored let now: () -> Date

  /// This month's budget progress. `nil` when the read threw, which is distinct
  /// from `[]`, a month with no budgets.
  private(set) var progress: [BudgetProgress]?
  /// The category worth budgeting next, with its three-month average.
  private(set) var suggestion: (slice: CategorySlice, averageMinor: Int)?
  /// Series the store shows, soonest first. A dismissed series is absent.
  private(set) var series: [RecurringSeries] = []
  private(set) var recurringState: RecurringState = .unavailable
  /// Set when a dismissal was refused. The row stays, and the screen says so.
  private(set) var dismissFailed = false

  init(
    insightsStore: InsightsStore,
    recurringStore: (any RecurringInsightsStore)?,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.insightsStore = insightsStore
    self.recurringStore = recurringStore
    self.calendar = calendar
    self.now = now
  }

  /// The month's totals, or `nil` with no budgets or when the read failed.
  var totals: BudgetTotals.Totals? {
    progress.flatMap { BudgetTotals.compute($0) }
  }

  /// The monthly total of every series shown. Detection is monthly only, so the
  /// sum is a month's cost.
  var monthlyRecurringMinor: Int {
    series.reduce(0) { $0 + $1.amountMinor }
  }

  /// Reads the month's budgets, the suggestion and the recurring series. Each read
  /// is independent: one failing does not blank the others.
  func load() {
    let parts = calendar.dateComponents([.year, .month], from: now())
    do {
      progress = try insightsStore.budgetProgress(year: parts.year ?? 1970, month: parts.month ?? 1)
    } catch {
      progress = nil
    }

    if let progress {
      do {
        let insights = try insightsStore.insights(for: .trailingMonths(3))
        suggestion = PlanLogic.suggestion(
          byCategory3m: insights.byCategory,
          budgeted: Set(progress.map(\.id))
        )
      } catch {
        suggestion = nil
      }
    } else {
      suggestion = nil
    }

    guard let recurringStore else {
      series = []
      recurringState = .unavailable
      return
    }
    do {
      series = try recurringStore.recurringSeries()
      recurringState = .loaded
    } catch {
      series = []
      recurringState = .failed
    }
  }

  /// "Not recurring": the store hides the series on this device, then the list is
  /// read again so the row leaves only after the store has accepted the change.
  func dismiss(seriesID: String) {
    guard let recurringStore else { return }
    do {
      try recurringStore.dismiss(seriesID: seriesID)
    } catch {
      dismissFailed = true
      return
    }
    dismissFailed = false
    load()
  }
}
