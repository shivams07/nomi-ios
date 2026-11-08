import Foundation
import NomiCore

// clt-harness: include

/// Pure period arithmetic for the Reports basis toggle — kept free of SwiftUI
/// and `@Model` types so it is directly unit-testable. Deliberately NOT
/// shared with `Dashboard/DashboardPeriod` (same shape, same math): this
/// unit's file boundary excludes `Dashboard/**`, and prior units (Accounts,
/// Budgets) established the pattern of not depending on another unit's
/// still-owned directory even where the type would be technically
/// accessible — see `BudgetRowSummary`'s note in `Budgets/BudgetsScreen.swift`.
/// The one thing that must NOT be duplicated is period-*boundary*
/// resolution itself (`NomiCore.dateRange(for:calendar:)` stays the sole
/// source of truth per design §2.3) — this type only decides which
/// `InsightPeriod` case the toggle is currently on.
enum ReportsPeriod {
  static func period(basis: PeriodBasis, anchor: Date, calendar: Calendar = .current) -> InsightPeriod {
    switch basis {
    case .calendarMonth:
      let components = calendar.dateComponents([.year, .month], from: anchor)
      return .month(year: components.year ?? 1970, month: components.month ?? 1)
    case .financialYear:
      let components = calendar.dateComponents([.year, .month], from: anchor)
      let month = components.month ?? 1
      let year = components.year ?? 1970
      let startingYear = month >= 4 ? year : year - 1
      return .financialYear(startingYear: startingYear)
    }
  }

  static func priorPeriod(for period: InsightPeriod) -> InsightPeriod? {
    switch period {
    case .month(let year, let month):
      return month == 1 ? .month(year: year - 1, month: 12) : .month(year: year, month: month - 1)
    case .financialYear(let startingYear):
      return .financialYear(startingYear: startingYear - 1)
    case .trailingMonths, .allTime:
      return nil
    }
  }

  /// F6: the toggle had no upper bound and could page into an empty future
  /// period. Refuses the shift outright — returns `anchor` unchanged — when
  /// the shifted period would start after `now`, rather than letting the
  /// screen render a period nothing has happened in yet.
  static func shiftedAnchor(
    _ anchor: Date, basis: PeriodBasis, by delta: Int, calendar: Calendar = .current, now: Date = Date()
  ) -> Date {
    let shifted = rawShift(anchor, basis: basis, by: delta, calendar: calendar)
    return startsAfter(now, basis: basis, anchor: shifted, calendar: calendar) ? anchor : shifted
  }

  /// The toggle's disabled-chevron state — whether a shift *would* be
  /// allowed, without performing it. Same rule `shiftedAnchor` itself
  /// enforces.
  static func canShift(
    _ anchor: Date, basis: PeriodBasis, by delta: Int, calendar: Calendar = .current, now: Date = Date()
  ) -> Bool {
    let shifted = rawShift(anchor, basis: basis, by: delta, calendar: calendar)
    return !startsAfter(now, basis: basis, anchor: shifted, calendar: calendar)
  }

  private static func rawShift(_ anchor: Date, basis: PeriodBasis, by delta: Int, calendar: Calendar) -> Date {
    switch basis {
    case .calendarMonth:
      return calendar.date(byAdding: .month, value: delta, to: anchor) ?? anchor
    case .financialYear:
      return calendar.date(byAdding: .year, value: delta, to: anchor) ?? anchor
    }
  }

  private static func startsAfter(_ now: Date, basis: PeriodBasis, anchor: Date, calendar: Calendar) -> Bool {
    let candidate = period(basis: basis, anchor: anchor, calendar: calendar)
    return dateRange(for: candidate, calendar: calendar, now: now).lowerBound > now
  }

  /// The period pill's menu anchors, same rule as HM1's `DashboardPeriod`:
  /// 12 calendar months with this month first, or 3 financial years (12 would
  /// reach years with no data).
  static func recentAnchors(basis: PeriodBasis, now: Date, calendar: Calendar = .current) -> [Date] {
    let count = basis == .calendarMonth ? 12 : 3
    let component: Calendar.Component = basis == .calendarMonth ? .month : .year
    return (0..<count).compactMap { calendar.date(byAdding: component, value: -$0, to: now) }
  }

  /// The Spent / Received delta line, "up ₹6,420 vs last period". Whole-rupee
  /// changes drop the ".00", as the artboard does. `nil` when there is no
  /// prior period to compare, which the screen words itself.
  static func changeCopy(current: Int, prior: Int?) -> String? {
    guard let prior else { return nil }
    let change = current - prior
    if change == 0 {
      return "No change vs last period"
    }
    var amount = NomiFormatters.amountString(minor: abs(change))
    if abs(change) % 100 == 0, amount.hasSuffix(".00") {
      amount.removeLast(3)
    }
    let direction = change > 0 ? "up" : "down"
    return "\(direction) \(amount) vs last period"
  }

  static func label(for period: InsightPeriod, calendar: Calendar = .current) -> String {
    switch period {
    case .month(let year, let month):
      var components = DateComponents()
      components.year = year
      components.month = month
      components.day = 1
      let date = calendar.date(from: components) ?? Date()
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_IN")
      formatter.dateFormat = "MMMM yyyy"
      return formatter.string(from: date)
    case .financialYear(let startingYear):
      return "FY \(startingYear)–\(String(format: "%02d", (startingYear + 1) % 100))"
    case .trailingMonths(let months):
      return "Last \(months) months"
    case .allTime:
      return "All time"
    }
  }

  /// The trend window per basis — 6 trailing months on the calendar-month
  /// toggle, 12 on the financial-year toggle, matching the design note
  /// ("6 or 12 months"). Both windows are still trailing-from-now, not
  /// aligned to the selected period; `InsightsStore.trend(months:)` has no
  /// other shape to request from.
  static func trendMonths(for basis: PeriodBasis) -> Int {
    switch basis {
    case .calendarMonth: return 6
    case .financialYear: return 12
    }
  }
}

/// The bar chart's series, pure so the day arithmetic is testable. A calendar
/// month shows one bar per day; a financial year shows the trend's monthly
/// debit bars instead (the trend rule above), because 365 bars carry no
/// readable shape.
enum ReportsSpendSeries {
  /// Day-of-month debit totals, index 0 = day 1, zero-filled. `nil` for any
  /// period that is not a calendar month.
  static func dailyDebit(period: InsightPeriod, byDay: [DayBucket], calendar: Calendar = .current) -> [Int]? {
    guard case .month(let year, let month) = period else { return nil }
    guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
          let dayCount = calendar.range(of: .day, in: .month, for: start)?.count else {
      return nil
    }
    var values = Array(repeating: 0, count: dayCount)
    for bucket in byDay where calendar.isDate(bucket.id, equalTo: start, toGranularity: .month) {
      let index = calendar.component(.day, from: bucket.id) - 1
      if values.indices.contains(index) {
        values[index] += bucket.debitMinor
      }
    }
    return values
  }

  /// The index of today's bar when the period is the current calendar month;
  /// `nil` otherwise.
  static func todayIndex(period: InsightPeriod, now: Date, calendar: Calendar = .current) -> Int? {
    guard case .month = period else { return nil }
    let current = ReportsPeriod.period(basis: .calendarMonth, anchor: now, calendar: calendar)
    guard current == period else { return nil }
    return calendar.component(.day, from: now) - 1
  }

  /// The bar drawn in full navy: today's bar when it exists, else the last bar.
  static func highlightIndex(count: Int, todayIndex: Int?) -> Int? {
    guard count > 0 else { return nil }
    guard let todayIndex, (0..<count).contains(todayIndex) else { return count - 1 }
    return todayIndex
  }

  /// The chart's spoken value, "Highest on day 14, ₹5,420.00", or "No spend"
  /// when every bar is zero. `label` names the bar at an index.
  static func peakDescription(values: [Int], label: (Int) -> String) -> String {
    guard let peak = values.indices.max(by: { values[$0] < values[$1] }), values[peak] > 0 else {
      return "No spend"
    }
    return "Highest \(label(peak)), \(NomiFormatters.amountString(minor: values[peak]))"
  }
}
