import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// The Plan tab's pure rules (S7): pace, days left, the per-day figure and the
/// suggestion. Dates are built in one calendar, so no test depends on the zone
/// the machine runs in.
final class PlanLogicTests: XCTestCase {
  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }()

  private func date(year: Int = 2026, month: Int, day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  private func slice(_ name: String, total: Int, id: UUID = UUID()) -> CategorySlice {
    CategorySlice(
      id: id,
      name: name,
      symbolName: "bag",
      paletteSlot: 1,
      totalMinor: total,
      share: 0
    )
  }

  // MARK: - Pace

  /// (day - 1 + 0.5) / daysInMonth. November 2026 has 30 days.
  func testPaceOnTheFirstIsHalfADayIntoTheMonth() {
    let pace = PlanLogic.pace(today: date(month: 11, day: 1), month: (2026, 11), calendar: calendar)
    XCTAssertEqual(pace, 0.5 / 30, accuracy: 1e-9)
  }

  func testPaceOnTheFourteenthIsThirteenAndAHalfDays() {
    let pace = PlanLogic.pace(today: date(month: 11, day: 14), month: (2026, 11), calendar: calendar)
    XCTAssertEqual(pace, 13.5 / 30, accuracy: 1e-9)
  }

  func testPaceOnTheLastDayIsJustBelowOne() {
    let pace = PlanLogic.pace(today: date(month: 11, day: 30), month: (2026, 11), calendar: calendar)
    XCTAssertEqual(pace, 29.5 / 30, accuracy: 1e-9)
  }

  /// February 2026 has 28 days, so the first is 0.5 / 28, not 0.5 / 30.
  func testPaceUsesTheLengthOfTheMonth() {
    let pace = PlanLogic.pace(today: date(month: 2, day: 1), month: (2026, 2), calendar: calendar)
    XCTAssertEqual(pace, 0.5 / 28, accuracy: 1e-9)
  }

  // MARK: - Days left

  /// Today counts: 14 November in a 30-day month leaves 17 days.
  func testDaysLeftCountsTodayInclusive() {
    XCTAssertEqual(PlanLogic.daysLeft(today: date(month: 11, day: 14), calendar: calendar), 17)
  }

  func testDaysLeftOnTheLastDayIsOne() {
    XCTAssertEqual(PlanLogic.daysLeft(today: date(month: 11, day: 30), calendar: calendar), 1)
  }

  func testDaysLeftOnTheFirstIsTheWholeMonth() {
    XCTAssertEqual(PlanLogic.daysLeft(today: date(month: 11, day: 1), calendar: calendar), 30)
  }

  func testDaysLeftFollowsTheLengthOfFebruary() {
    XCTAssertEqual(PlanLogic.daysLeft(today: date(month: 2, day: 1), calendar: calendar), 28)
  }

  // MARK: - Per day

  /// ₹1,321 over 17 days is ₹77.7 a day, and the figure floors to ₹77. The
  /// canvas shows ₹78, which would overshoot the promise "keeps you under".
  func testPerDayFloorsToWholeRupees() {
    XCTAssertEqual(PlanLogic.perDay(remainingMinor: 1_321_00, daysLeft: 17), 77)
  }

  func testPerDayIgnoresPaiseBeforeDividing() {
    XCTAssertEqual(PlanLogic.perDay(remainingMinor: 1_321_50, daysLeft: 17), 77)
  }

  func testPerDayIsZeroWhenOver() {
    XCTAssertEqual(PlanLogic.perDay(remainingMinor: -965_00, daysLeft: 17), 0)
  }

  func testPerDayIsZeroWithNoDaysLeft() {
    XCTAssertEqual(PlanLogic.perDay(remainingMinor: 1_321_00, daysLeft: 0), 0)
  }

  // MARK: - Suggestion

  func testSuggestionPicksTheLargestUnbudgetedCategory() {
    let budgetedID = UUID()
    let slices = [
      slice("Groceries", total: 9_000_00, id: budgetedID),
      slice("Bills", total: 6_000_00),
      slice("Travel", total: 7_000_00),
    ]
    let suggestion = PlanLogic.suggestion(byCategory3m: slices, budgeted: [budgetedID])
    XCTAssertEqual(suggestion?.slice.name, "Travel")
  }

  /// The average is the three-month total divided by three, floored in minor
  /// units: 7,001 paise over three months is 2,333 paise a month.
  func testSuggestionFloorsTheAverage() {
    let slices = [slice("Bills", total: 7_001)]
    XCTAssertEqual(PlanLogic.suggestion(byCategory3m: slices, budgeted: [])?.averageMinor, 2_333)
  }

  /// The uncategorised sentinel is never a sensible budget, however large.
  func testSuggestionSkipsUncategorisedSpend() {
    let slices = [
      slice("Uncategorized", total: 50_000_00, id: NomiCore.Category.uncategorizedID),
      slice("Bills", total: 6_000_00),
    ]
    XCTAssertEqual(PlanLogic.suggestion(byCategory3m: slices, budgeted: [])?.slice.name, "Bills")
  }

  func testSuggestionIsNilWhenEveryCategoryIsBudgeted() {
    let id = UUID()
    let slices = [slice("Bills", total: 6_000_00, id: id)]
    XCTAssertNil(PlanLogic.suggestion(byCategory3m: slices, budgeted: [id]))
  }

  func testSuggestionIgnoresCategoriesWithNoSpend() {
    XCTAssertNil(PlanLogic.suggestion(byCategory3m: [slice("Travel", total: 0)], budgeted: []))
  }
}
