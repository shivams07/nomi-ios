import Foundation
import XCTest

@testable import NomiUI

/// The Plan tab's rupee and date copy (S7). Dates are built in one calendar, and the
/// zone test runs the day read through a zone far from the calendar's, so the copy
/// keeps the day it was built with on any machine.
final class PlanFormatTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }()

  private func date(year: Int = 2026, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  // MARK: - Money

  func testWholeRupeesPrintWithoutDecimals() {
    XCTAssertEqual(PlanLogic.money(minor: 1_321_00), "₹1,321")
  }

  func testPaiseKeepTwoDecimals() {
    XCTAssertEqual(PlanLogic.money(minor: 1_321_50), "₹1,321.50")
  }

  func testIndianGroupingAboveAHundredThousand() {
    XCTAssertEqual(PlanLogic.money(minor: 1_00_00_000_00), "₹1,00,00,000")
  }

  /// Callers pass a magnitude as the label, so a negative figure prints without a sign.
  func testMagnitudeOnlyForNegatives() {
    XCTAssertEqual(PlanLogic.money(minor: -965_00), "₹965")
  }

  func testZeroIsRupeesZero() {
    XCTAssertEqual(PlanLogic.money(minor: 0), "₹0")
  }

  // MARK: - Day and month

  func testDayMonthIsDayThenShortMonth() {
    XCTAssertEqual(PlanLogic.dayMonth(date(month: 12, day: 1), calendar: calendar), "1 Dec")
  }

  /// 00:30 on 1 December in Kolkata is 30 November in Los Angeles. The copy must read the
  /// day in the calendar that built the date.
  func testDayMonthKeepsTheDayAcrossAZoneBoundary() {
    XCTAssertEqual(PlanLogic.dayMonth(date(month: 12, day: 1, hour: 0, minute: 30), calendar: calendar), "1 Dec")
  }

  func testMonthNameIsTheFullName() {
    XCTAssertEqual(PlanLogic.monthName(date(month: 11, day: 16), calendar: calendar), "November")
    XCTAssertEqual(PlanLogic.monthName(date(month: 2, day: 3), calendar: calendar), "February")
  }

  func testFirstOfNextMonthIsTheFirstAtMidnight() throws {
    let next = try XCTUnwrap(PlanLogic.firstOfNextMonth(after: date(month: 11, day: 16), calendar: calendar))
    XCTAssertEqual(calendar.component(.month, from: next), 12)
    XCTAssertEqual(calendar.component(.day, from: next), 1)
    XCTAssertEqual(calendar.component(.hour, from: next), 0)
  }

  func testFirstOfNextMonthRollsOverTheYear() throws {
    let next = try XCTUnwrap(PlanLogic.firstOfNextMonth(after: date(month: 12, day: 20), calendar: calendar))
    XCTAssertEqual(calendar.component(.year, from: next), 2027)
    XCTAssertEqual(calendar.component(.month, from: next), 1)
    XCTAssertEqual(calendar.component(.day, from: next), 1)
  }
}
