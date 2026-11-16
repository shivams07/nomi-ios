import Foundation
import NomiCore
import Observation

/// Which total the Last 6 months bars draw. Its own type because
/// `NomiComparisonCopy.Kind` is not `Hashable`, which `NomiSegmented` needs.
enum ReportsBarKind: Hashable, Sendable {
  case spent
  case income
}

/// Insights' period state and reads (S6). The screen reads and drives this
/// model, and its body reads only these properties, so no store is read on a
/// render. `load()` runs from the screen's `.task(id:)`.
///
/// Every clock-dependent call takes `now`, so the basis and midnight rules are
/// testable without a clock. Months and days use the India calendar.
@Observable @MainActor final class ReportsModel {
  @ObservationIgnored private let insightsStore: InsightsStore
  /// The calendar every period and month is read in. `NomiCalendar.india`.
  @ObservationIgnored let calendar: Calendar

  /// Calendar month or financial year. Changed through `setBasis(_:now:)`.
  private(set) var basis: PeriodBasis
  /// Any day in the selected month, or the day the financial year is taken from.
  private(set) var anchor: Date
  /// `true` while the screen follows the clock (`PeriodAnchorPolicy`, R12b).
  private(set) var followsToday: Bool
  /// Which total the bars draw. Switching it reads nothing.
  var kind: ReportsBarKind = .spent
  /// The selected period's read. `nil` until the first `load()`.
  private(set) var insights: DashboardWiring.Load<PeriodInsights>?
  /// The bars' read: the six months ending with the period's month on the
  /// calendar basis, or the financial year's twelve months.
  private(set) var trend: DashboardWiring.Load<[MonthBucket]>?
  /// Bumped by a load-failed card's Try again. Part of the load key, so a bump
  /// reads both stores again.
  private(set) var retryToken = 0

  init(
    insightsStore: InsightsStore,
    basis: PeriodBasis,
    anchor: Date,
    followsToday: Bool = true,
    calendar: Calendar = NomiCalendar.india
  ) {
    self.insightsStore = insightsStore
    self.basis = basis
    self.anchor = anchor
    self.followsToday = followsToday
    self.calendar = calendar
  }

  var period: InsightPeriod {
    ReportsPeriod.period(basis: basis, anchor: anchor, calendar: calendar)
  }

  /// One read per store call. Both reads are for the same period. A failed read
  /// is `.failed`, not an empty result (F3).
  func load() {
    let selected = period
    insights = Self.read { try insightsStore.insights(for: selected) }
    trend = Self.read { try insightsStore.monthlyTrend(for: selected) }
  }

  func retry() {
    retryToken += 1
  }

  /// The basis picker. The picked basis follows today again, from `now`.
  func setBasis(_ basis: PeriodBasis, now: Date) {
    self.basis = basis
    anchor = now
    followsToday = true
  }

  /// A refresh: the cache generation changed, or the day did. Moves the anchor
  /// to `now` while the screen follows today, and leaves a picked period alone.
  func dayChanged(now: Date) {
    anchor = PeriodAnchorPolicy.anchorAfterRefresh(current: anchor, followsToday: followsToday, now: now)
  }

  /// The period pill's menu: one of the recent anchors, on the current basis.
  func pickAnchor(_ candidate: Date, now: Date) {
    anchor = candidate
    followsToday = PeriodAnchorPolicy.followsToday(afterPicking: candidate, basis: basis, now: now, calendar: calendar)
  }

  /// A bar tap: opens that month on the calendar basis.
  func selectMonth(_ bucket: MonthBucket, now: Date) {
    basis = .calendarMonth
    anchor = bucket.id
    followsToday = PeriodAnchorPolicy.followsToday(afterPicking: bucket.id, basis: .calendarMonth, now: now, calendar: calendar)
  }

  private static func read<T>(_ body: () throws -> T) -> DashboardWiring.Load<T> {
    do {
      return .loaded(try body())
    } catch {
      return .failed
    }
  }
}

extension DashboardWiring.Load {
  /// The payload of a loaded read, `nil` for a failed one.
  var loadedValue: T? {
    if case .loaded(let value) = self { return value }
    return nil
  }
}
