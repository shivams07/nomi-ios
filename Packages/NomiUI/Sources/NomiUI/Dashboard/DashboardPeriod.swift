import Foundation
import NomiCore

/// Pure period arithmetic for the dashboard's period selector — kept free of
/// SwiftUI and `@Model` types so it is directly unit-testable. The single
/// source of truth for how a calendar period turns into a range stays
/// `NomiCore.dateRange(for:calendar:now:)` (design §2.3); this type only
/// derives which `InsightPeriod` the selector is currently on, what its
/// comparison period is, and how to label both.
enum DashboardPeriod {
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

  /// `nil` only for the non-selector periods (`trailingMonths`, `allTime`) —
  /// the dashboard's own selector only ever produces `.month`/`.financialYear`,
  /// so this only returns `nil` for inputs the selector cannot itself produce.
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

  /// F6: the selector had no upper bound and could page into an empty future
  /// month. Refuses the shift outright — returns `anchor` unchanged — when
  /// the shifted period would start after `now`, rather than letting the
  /// screen render a period nothing has happened in yet.
  static func shiftedAnchor(
    _ anchor: Date, basis: PeriodBasis, by delta: Int, calendar: Calendar = .current, now: Date = Date()
  ) -> Date {
    let shifted = rawShift(anchor, basis: basis, by: delta, calendar: calendar)
    return startsAfter(now, basis: basis, anchor: shifted, calendar: calendar) ? anchor : shifted
  }

  /// The selector's disabled-chevron state — whether a shift *would* be
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
}
