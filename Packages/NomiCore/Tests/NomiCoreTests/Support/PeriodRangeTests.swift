import Foundation
import Testing
@testable import NomiCore

struct PeriodRangeTests {
  private var calendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return cal
  }

  @Test func financialYearStartsApril1() {
    let range = dateRange(for: .financialYear(startingYear: 2026), calendar: calendar)
    var components = DateComponents()
    components.year = 2026
    components.month = 4
    components.day = 1
    let expectedStart = calendar.date(from: components)!
    #expect(range.lowerBound == expectedStart)
  }

  @Test func financialYearEndsMarch31NextYear() {
    let range = dateRange(for: .financialYear(startingYear: 2026), calendar: calendar)
    var components = DateComponents()
    components.year = 2027
    components.month = 4
    components.day = 1
    let expectedEnd = calendar.date(from: components)!
    #expect(range.upperBound == expectedEnd)
  }

  @Test func march31IsInFinancialYear2025() {
    let range = dateRange(for: .financialYear(startingYear: 2025), calendar: calendar)
    var components = DateComponents()
    components.year = 2026
    components.month = 3
    components.day = 31
    let march31 = calendar.date(from: components)!
    #expect(range.contains(march31))
  }

  @Test func april1IsInFinancialYear2026NotThePriorOne() {
    let rangeCurrent = dateRange(for: .financialYear(startingYear: 2026), calendar: calendar)
    let rangePrior = dateRange(for: .financialYear(startingYear: 2025), calendar: calendar)
    var components = DateComponents()
    components.year = 2026
    components.month = 4
    components.day = 1
    let april1 = calendar.date(from: components)!
    #expect(rangeCurrent.contains(april1))
    #expect(!rangePrior.contains(april1))
  }

  @Test func calendarMonthRange() {
    let range = dateRange(for: .month(year: 2026, month: 2), calendar: calendar)
    var start = DateComponents()
    start.year = 2026
    start.month = 2
    start.day = 1
    var end = DateComponents()
    end.year = 2026
    end.month = 3
    end.day = 1
    #expect(range.lowerBound == calendar.date(from: start)!)
    #expect(range.upperBound == calendar.date(from: end)!)
  }

  // MARK: - R12a: trailing windows are whole calendar months

  /// A wall-clock moment in the test calendar, so each expectation reads as
  /// the IST date it names.
  private func ist(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  /// 14 Nov 2026, 09:00 IST: six months is June through November, and the
  /// window ends at the start of tomorrow.
  @Test func trailingSixMonthsStartsOnTheFirstOfTheMonthSixBack() {
    let now = ist(2026, 11, 14, 9)
    let range = dateRange(for: .trailingMonths(6), calendar: calendar, now: now)
    #expect(range == ist(2026, 6, 1)..<ist(2026, 11, 15))
  }

  /// `.trailingMonths(1)` is the current month so far, not the last thirty days.
  @Test func trailingOneMonthIsThisMonthSoFar() {
    let now = ist(2026, 11, 14, 9)
    let range = dateRange(for: .trailingMonths(1), calendar: calendar, now: now)
    #expect(range == ist(2026, 11, 1)..<ist(2026, 11, 15))
  }

  /// The window ends at the start of tomorrow whatever the hour of `now`, so
  /// a row dated later today is inside it.
  @Test func trailingWindowEndsAtTheStartOfTomorrowAtAnyHour() {
    let late = ist(2026, 11, 14, 23, 59)
    let range = dateRange(for: .trailingMonths(1), calendar: calendar, now: late)
    #expect(range.upperBound == ist(2026, 11, 15))
  }
}
