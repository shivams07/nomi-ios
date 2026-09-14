import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class RemainingBudgetCardTests: XCTestCase {
  private var ist: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return ist.date(from: components)!
  }

  func testPercentTextRoundsToWholeNumber() {
    XCTAssertEqual(RemainingBudgetPercent.text(0.335), "34%")
    XCTAssertEqual(RemainingBudgetPercent.text(0.9), "90%")
  }

  func testElapsedFractionMidwayThroughAThirtyDayMonth() {
    let fraction = RemainingBudgetPace.elapsedFraction(referenceDate: date(2026, 9, 14), calendar: ist)
    XCTAssertEqual(fraction, 14.0 / 30.0, accuracy: 0.0001)
  }

  func testElapsedFractionOnLastDayOfMonthIsOne() {
    let fraction = RemainingBudgetPace.elapsedFraction(referenceDate: date(2026, 9, 30), calendar: ist)
    XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
  }
}
