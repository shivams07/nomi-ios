import Foundation
import NomiCore

// clt-harness: include

/// The Ledger's period (G1, DEC-04). One definition of a period, shared with
/// Home: the range comes from `NomiCore.dateRange(for:)`, the sole place a
/// calendar month or financial year is computed, and the period from
/// `DashboardPeriod`. This type adds no date arithmetic of its own.
///
/// The calendar is passed in by the caller, who passes the one
/// `SwiftDataInsightsStore` is built with (`.current`). Never the India
/// calendar in `NomiCalendar`: that one is for dedupe keys, and a Ledger month
/// computed on it would not be the Home month for the same data.
enum LedgerPeriod {
  /// The half-open range of the period `basis` and `anchor` name.
  static func range(basis: PeriodBasis, anchor: Date, calendar: Calendar, now: Date) -> Range<Date> {
    dateRange(for: DashboardPeriod.period(basis: basis, anchor: anchor, calendar: calendar), calendar: calendar, now: now)
  }

  /// The anchor one period before `anchor`, for "Show <previous period>". Moves
  /// the anchor and nothing else; `DashboardPeriod` owns the arithmetic.
  static func previousAnchor(basis: PeriodBasis, anchor: Date, calendar: Calendar, now: Date) -> Date {
    DashboardPeriod.shiftedAnchor(anchor, basis: basis, by: -1, calendar: calendar, now: now)
  }

  /// The label of the period before `anchor`, e.g. "October 2026".
  static func previousLabel(basis: PeriodBasis, anchor: Date, calendar: Calendar, now: Date) -> String {
    let previous = previousAnchor(basis: basis, anchor: anchor, calendar: calendar, now: now)
    return DashboardPeriod.label(for: DashboardPeriod.period(basis: basis, anchor: previous, calendar: calendar), calendar: calendar)
  }
}
