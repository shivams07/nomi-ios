import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class ReportsPeriodTests: XCTestCase {
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
    let period = ReportsPeriod.period(basis: .calendarMonth, anchor: date(2026, 8), calendar: utc)
    XCTAssertEqual(period, .month(year: 2026, month: 8))
  }

  func testFinancialYearPeriodBeforeAprilRollsToPriorStartYear() {
    let period = ReportsPeriod.period(basis: .financialYear, anchor: date(2026, 2), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2025))
  }

  func testFinancialYearPeriodAtOrAfterAprilUsesSameStartYear() {
    let period = ReportsPeriod.period(basis: .financialYear, anchor: date(2026, 4), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2026))
  }

  /// The design's own flagged risk (§2.3): a transaction dated 31 Mar and one
  /// dated 1 Apr are one day apart but belong to different financial years.
  /// The anchor-to-period mapping must draw that line at midnight 1 Apr, not
  /// smear across it.
  func testFinancialYearAnchorOn31MarchIsPriorYear() {
    let period = ReportsPeriod.period(basis: .financialYear, anchor: date(2026, 3, 31), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2025))
  }

  func testFinancialYearAnchorOn1AprilIsNewYear() {
    let period = ReportsPeriod.period(basis: .financialYear, anchor: date(2026, 4, 1), calendar: utc)
    XCTAssertEqual(period, .financialYear(startingYear: 2026))
  }

  func testCalendarMonthAnchorsOn31MarchAnd1AprilAreDifferentMonths() {
    let march = ReportsPeriod.period(basis: .calendarMonth, anchor: date(2026, 3, 31), calendar: utc)
    let april = ReportsPeriod.period(basis: .calendarMonth, anchor: date(2026, 4, 1), calendar: utc)
    XCTAssertEqual(march, .month(year: 2026, month: 3))
    XCTAssertEqual(april, .month(year: 2026, month: 4))
  }

  func testPriorPeriodForJanuaryRollsBackAYear() {
    let prior = ReportsPeriod.priorPeriod(for: .month(year: 2026, month: 1))
    XCTAssertEqual(prior, .month(year: 2025, month: 12))
  }

  func testPriorPeriodForMidYearMonthDecrementsMonth() {
    let prior = ReportsPeriod.priorPeriod(for: .month(year: 2026, month: 8))
    XCTAssertEqual(prior, .month(year: 2026, month: 7))
  }

  func testPriorPeriodForFinancialYearDecrementsStartingYear() {
    let prior = ReportsPeriod.priorPeriod(for: .financialYear(startingYear: 2026))
    XCTAssertEqual(prior, .financialYear(startingYear: 2025))
  }

  func testPriorPeriodIsNilForTrailingMonthsAndAllTime() {
    XCTAssertNil(ReportsPeriod.priorPeriod(for: .trailingMonths(6)))
    XCTAssertNil(ReportsPeriod.priorPeriod(for: .allTime))
  }

  /// `now` is deliberately after the shifted-to month here, so this pins the
  /// ordinary (non-clamped) case — F6's clamp is exercised separately below.
  func testShiftedAnchorMovesByOneMonthForCalendarBasis() {
    let shifted = ReportsPeriod.shiftedAnchor(
      date(2026, 8), basis: .calendarMonth, by: 1, calendar: utc, now: date(2026, 9, 15))
    XCTAssertEqual(utc.component(.month, from: shifted), 9)
  }

  func testShiftedAnchorMovesByOneYearForFinancialYearBasis() {
    let shifted = ReportsPeriod.shiftedAnchor(
      date(2026, 8), basis: .financialYear, by: -1, calendar: utc, now: date(2026, 8, 15))
    XCTAssertEqual(utc.component(.year, from: shifted), 2025)
  }

  /// F6: no upper bound on the toggle used to mean paging forward from the
  /// current month landed on an empty future period. This FAILS on `main`,
  /// where `shiftedAnchor` had no `now` to clamp against at all.
  func testShiftedAnchorFromTheCurrentMonthDoesNotAdvanceIntoTheFuture() {
    let now = date(2026, 9, 15)
    let shifted = ReportsPeriod.shiftedAnchor(now, basis: .calendarMonth, by: 1, calendar: utc, now: now)
    XCTAssertEqual(shifted, now, "the anchor is unchanged — October has not started")
  }

  func testShiftedAnchorFromLastMonthAdvancesToTheCurrentMonth() {
    let now = date(2026, 9, 15)
    let shifted = ReportsPeriod.shiftedAnchor(date(2026, 8), basis: .calendarMonth, by: 1, calendar: utc, now: now)
    XCTAssertEqual(utc.component(.month, from: shifted), 9)
  }

  func testShiftedAnchorFromTheCurrentFinancialYearDoesNotAdvanceIntoTheFuture() {
    let now = date(2026, 9, 15)
    let shifted = ReportsPeriod.shiftedAnchor(now, basis: .financialYear, by: 1, calendar: utc, now: now)
    XCTAssertEqual(shifted, now, "the anchor is unchanged — FY 2027-28 has not started")
  }

  func testShiftedAnchorFromLastFinancialYearAdvancesToTheCurrentOne() {
    let now = date(2026, 9, 15)
    let shifted = ReportsPeriod.shiftedAnchor(date(2025, 9), basis: .financialYear, by: 1, calendar: utc, now: now)
    XCTAssertEqual(
      ReportsPeriod.period(basis: .financialYear, anchor: shifted, calendar: utc),
      .financialYear(startingYear: 2026))
  }

  func testCanShiftIsFalseForwardFromTheCurrentMonth() {
    let now = date(2026, 9, 15)
    XCTAssertFalse(ReportsPeriod.canShift(now, basis: .calendarMonth, by: 1, calendar: utc, now: now))
  }

  func testCanShiftIsTrueForwardFromLastMonth() {
    let now = date(2026, 9, 15)
    XCTAssertTrue(ReportsPeriod.canShift(date(2026, 8), basis: .calendarMonth, by: 1, calendar: utc, now: now))
  }

  func testCanShiftIsAlwaysTrueGoingBackward() {
    let now = date(2026, 9, 15)
    XCTAssertTrue(ReportsPeriod.canShift(now, basis: .calendarMonth, by: -1, calendar: utc, now: now))
  }

  func testFinancialYearLabelSpansTwoCalendarYears() {
    let label = ReportsPeriod.label(for: .financialYear(startingYear: 2026))
    XCTAssertTrue(label.contains("2026"))
    XCTAssertTrue(label.contains("27"))
  }

  func testTrendMonthsIsSixForCalendarBasisAndTwelveForFinancialYear() {
    XCTAssertEqual(ReportsPeriod.trendMonths(for: .calendarMonth), 6)
    XCTAssertEqual(ReportsPeriod.trendMonths(for: .financialYear), 12)
  }
}
