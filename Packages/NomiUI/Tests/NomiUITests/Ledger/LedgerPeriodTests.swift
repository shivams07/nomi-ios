import Foundation
import NomiCore
import Testing

@testable import NomiUI

// clt-harness: include

/// G1, DEC-04 and A-04.2: the Ledger's period range, under two calendars
/// (Asia/Kolkata and America/Los_Angeles), so no boundary depends on the zone
/// the machine runs in. The range is `NomiCore.dateRange`, so these check the
/// wiring and the edges, not a second calendar implementation.
struct LedgerPeriodTests {
  /// Auckland is ahead of UTC and Los Angeles behind, so a month boundary
  /// falls on a different wall-clock day in each: no zone is the test's own.
  private static let zones = ["Asia/Kolkata", "America/Los_Angeles", "Pacific/Auckland"]

  private func calendar(_ identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  /// A wall-clock moment in `calendar`'s zone.
  private func at(
    _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int,
    hour: Int = 12, minute: Int = 0, second: Int = 0
  ) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
  }

  // MARK: - Rollovers and edges

  @Test(arguments: zones)
  func decemberThirtyFirstRollsOverToJanuaryFirst(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 12, 31, hour: 23, minute: 59, second: 59)
    let december = LedgerPeriod.range(basis: .calendarMonth, anchor: now, calendar: cal, now: now)
    #expect(december == at(cal, 2026, 12, 1, hour: 0)..<at(cal, 2027, 1, 1, hour: 0))

    let january = LedgerPeriod.range(
      basis: .calendarMonth, anchor: at(cal, 2027, 1, 1, hour: 0), calendar: cal, now: now)
    #expect(january.lowerBound == december.upperBound, "January starts exactly where December ends")
    #expect(december.contains(at(cal, 2026, 12, 31, hour: 23, minute: 59, second: 59)))
    #expect(!december.contains(at(cal, 2027, 1, 1, hour: 0)), "1 January 00:00:00 is not December")
  }

  @Test(arguments: zones)
  func thirtyFirstMarchEndsTheFinancialYearAtTheFirstOfApril(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 6, 1)
    let fy2025 = LedgerPeriod.range(
      basis: .financialYear, anchor: at(cal, 2026, 3, 31, hour: 23, minute: 59, second: 59), calendar: cal, now: now)
    #expect(fy2025 == at(cal, 2025, 4, 1, hour: 0)..<at(cal, 2026, 4, 1, hour: 0))

    // 31 Mar 23:59:59 is in the year that is ending; 1 Apr 00:00:00 is in the next.
    #expect(fy2025.contains(at(cal, 2026, 3, 31, hour: 23, minute: 59, second: 59)))
    #expect(!fy2025.contains(at(cal, 2026, 4, 1, hour: 0)))

    let fy2026 = LedgerPeriod.range(
      basis: .financialYear, anchor: at(cal, 2026, 4, 1, hour: 0), calendar: cal, now: now)
    #expect(fy2026.contains(at(cal, 2026, 4, 1, hour: 0)))
    #expect(fy2026.lowerBound == fy2025.upperBound)
  }

  @Test(arguments: zones)
  func leapDayBelongsToFebruary(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2028, 3, 15)
    let february = LedgerPeriod.range(
      basis: .calendarMonth, anchor: at(cal, 2028, 2, 29), calendar: cal, now: now)
    #expect(february == at(cal, 2028, 2, 1, hour: 0)..<at(cal, 2028, 3, 1, hour: 0))
    #expect(february.contains(at(cal, 2028, 2, 29, hour: 23, minute: 59, second: 59)))
    #expect(!february.contains(at(cal, 2028, 3, 1, hour: 0)))
  }

  /// The bounds are half-open, as `dateRange` makes them: a row at `lowerBound`
  /// is in the period, and a row at `upperBound` is in the next one.
  @Test(arguments: zones)
  func lowerBoundIsInAndUpperBoundIsOut(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 11, 8)
    let november = LedgerPeriod.range(basis: .calendarMonth, anchor: now, calendar: cal, now: now)
    #expect(november.contains(november.lowerBound))
    #expect(!november.contains(november.upperBound))
  }

  // MARK: - One definition

  /// `LedgerPeriod.range` is `NomiCore.dateRange` over Home's period, for every
  /// month and financial year in a two-year span. Any arithmetic the Ledger
  /// added of its own would show here as a different range.
  @Test(arguments: zones)
  func rangeEqualsTheCoreRangeForEveryPeriodSpanned(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 11, 8)
    for offset in 0..<24 {
      let anchor = at(cal, 2025 + offset / 12, offset % 12 + 1, 15)
      let period = DashboardPeriod.period(basis: .calendarMonth, anchor: anchor, calendar: cal)
      #expect(
        LedgerPeriod.range(basis: .calendarMonth, anchor: anchor, calendar: cal, now: now)
          == dateRange(for: period, calendar: cal, now: now))
    }
    for year in 2025...2027 {
      let anchor = at(cal, year, 7, 15)
      let period = DashboardPeriod.period(basis: .financialYear, anchor: anchor, calendar: cal)
      #expect(
        LedgerPeriod.range(basis: .financialYear, anchor: anchor, calendar: cal, now: now)
          == dateRange(for: period, calendar: cal, now: now))
    }
  }

  // MARK: - Stepping back

  @Test(arguments: zones)
  func showPreviousMovesTheAnchorBackExactlyOnePeriod(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 11, 8)

    let fromMarch = LedgerPeriod.previousAnchor(
      basis: .calendarMonth, anchor: at(cal, 2026, 3, 15), calendar: cal, now: now)
    #expect(DashboardPeriod.period(basis: .calendarMonth, anchor: fromMarch, calendar: cal) == .month(year: 2026, month: 2))

    let fromJanuary = LedgerPeriod.previousAnchor(
      basis: .calendarMonth, anchor: at(cal, 2026, 1, 15), calendar: cal, now: now)
    #expect(DashboardPeriod.period(basis: .calendarMonth, anchor: fromJanuary, calendar: cal) == .month(year: 2025, month: 12))

    let fromFY2026 = LedgerPeriod.previousAnchor(
      basis: .financialYear, anchor: at(cal, 2026, 4, 15), calendar: cal, now: now)
    #expect(DashboardPeriod.period(basis: .financialYear, anchor: fromFY2026, calendar: cal) == .financialYear(startingYear: 2025))
  }

  @Test(arguments: zones)
  func showPreviousNamesThePreviousPeriod(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 11, 8)
    #expect(
      LedgerPeriod.previousLabel(basis: .calendarMonth, anchor: now, calendar: cal, now: now) == "October 2026")
  }

  /// The menu offers only periods that have started: no period after the current
  /// one can be selected (DEC-04, item 3 and acceptance 5).
  @Test(arguments: zones)
  func noOfferedPeriodStartsAfterNow(zone: String) {
    let cal = calendar(zone)
    let now = at(cal, 2026, 11, 8)
    for anchor in DashboardPeriod.recentAnchors(basis: .calendarMonth, now: now, calendar: cal) {
      let range = LedgerPeriod.range(basis: .calendarMonth, anchor: anchor, calendar: cal, now: now)
      #expect(range.lowerBound <= now)
    }
    #expect(
      !DashboardPeriod.canShift(now, basis: .calendarMonth, by: 1, calendar: cal, now: now),
      "the period after the current one is refused")
  }
}
