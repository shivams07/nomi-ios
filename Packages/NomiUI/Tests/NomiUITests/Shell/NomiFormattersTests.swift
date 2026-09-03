import XCTest
@testable import NomiUI

final class NomiFormattersTests: XCTestCase {
  func testDayMonthAdaptiveOmitsYearWithinTheSameCalendarYear() {
    let reference = date(year: 2026, month: 9, day: 3)
    let sameYear = date(year: 2026, month: 1, day: 15)

    let text = NomiFormatters.dayMonthAdaptive(sameYear, relativeTo: reference)

    XCTAssertFalse(text.contains("2026"))
  }

  func testDayMonthAdaptiveIncludesYearAcrossCalendarYears() {
    let reference = date(year: 2026, month: 9, day: 3)
    let priorYear = date(year: 2025, month: 12, day: 20)

    let text = NomiFormatters.dayMonthAdaptive(priorYear, relativeTo: reference)

    XCTAssertTrue(text.contains("2025"))
  }

  private func date(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar(identifier: .gregorian).date(from: components)!
  }
}
