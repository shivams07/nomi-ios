import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class DashboardPeriodTests: XCTestCase {
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return utc.date(from: components)!
  }

  func testCalendarMonthPeriodFromAnchor() {
    let period = DashboardPeriod.period(basis: .calendarMonth, anchor: date(2026, 8), calendar: utc)
    XCTAssertEqual(period, .month(year: 2026, month: 8))
  }

  func testFinancialYearPeriodBeforeAprilRollsToPriorStartYear() {
    let period = DashboardPeriod.period(basis: .financialYear, anchor: date(2026, 2), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2025))
  }

  func testFinancialYearPeriodAtOrAfterAprilUsesSameStartYear() {
    let period = DashboardPeriod.period(basis: .financialYear, anchor: date(2026, 4), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2026))
  }

  func testPriorPeriodForJanuaryRollsBackAYear() {
    let prior = DashboardPeriod.priorPeriod(for: .month(year: 2026, month: 1))
    XCTAssertEqual(prior, .month(year: 2025, month: 12))
  }

  func testPriorPeriodForMidYearMonthDecrementsMonth() {
    let prior = DashboardPeriod.priorPeriod(for: .month(year: 2026, month: 8))
    XCTAssertEqual(prior, .month(year: 2026, month: 7))
  }

  func testPriorPeriodForFinancialYearDecrementsStartingYear() {
    let prior = DashboardPeriod.priorPeriod(for: .financialYear(startingYear: 2026))
    XCTAssertEqual(prior, .financialYear(startingYear: 2025))
  }

  func testPriorPeriodIsNilForTrailingMonthsAndAllTime() {
    XCTAssertNil(DashboardPeriod.priorPeriod(for: .trailingMonths(6)))
    XCTAssertNil(DashboardPeriod.priorPeriod(for: .allTime))
  }

  func testShiftedAnchorMovesByOneMonthForCalendarBasis() {
    let shifted = DashboardPeriod.shiftedAnchor(date(2026, 8), basis: .calendarMonth, by: 1, calendar: utc)
    XCTAssertEqual(utc.component(.month, from: shifted), 9)
  }

  func testShiftedAnchorMovesByOneYearForFinancialYearBasis() {
    let shifted = DashboardPeriod.shiftedAnchor(date(2026, 8), basis: .financialYear, by: -1, calendar: utc)
    XCTAssertEqual(utc.component(.year, from: shifted), 2025)
  }

  func testFinancialYearLabelSpansTwoCalendarYears() {
    let label = DashboardPeriod.label(for: .financialYear(startingYear: 2026))
    XCTAssertTrue(label.contains("2026"))
    XCTAssertTrue(label.contains("27"))
  }
}
