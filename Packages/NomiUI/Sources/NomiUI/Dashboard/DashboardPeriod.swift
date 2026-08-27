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

  static func shiftedAnchor(_ anchor: Date, basis: PeriodBasis, by delta: Int, calendar: Calendar = .current) -> Date {
    switch basis {
    case .calendarMonth:
      return calendar.date(byAdding: .month, value: delta, to: anchor) ?? anchor
    case .financialYear:
      return calendar.date(byAdding: .year, value: delta, to: anchor) ?? anchor
    }
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
