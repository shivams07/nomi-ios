import Foundation
import NomiCore

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
