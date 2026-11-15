import Foundation
import XCTest
@testable import NomiUI

/// R12b. Whether Home and Insights follow today after midnight. A user who has
/// picked a period that contains today follows the clock; a user who has picked
/// any other period keeps it.
final class PeriodAnchorPolicyTests: XCTestCase {
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int = 15, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return utc.date(from: components)!
  }

  func testPickingTheCurrentMonthFollowsToday() {
    let now = date(2026, 11, 15)
    XCTAssertTrue(
      PeriodAnchorPolicy.followsToday(afterPicking: now, basis: .calendarMonth, now: now, calendar: utc)
    )
  }

  func testPickingLastMonthDoesNotFollowToday() {
    let now = date(2026, 11, 15)
    XCTAssertFalse(
      PeriodAnchorPolicy.followsToday(afterPicking: date(2026, 10, 15), basis: .calendarMonth, now: now, calendar: utc)
    )
  }

  func testPickingTheCurrentFinancialYearFollowsToday() {
    let now = date(2026, 11, 15)
    XCTAssertTrue(
      PeriodAnchorPolicy.followsToday(afterPicking: date(2026, 4, 1), basis: .financialYear, now: now, calendar: utc)
    )
  }

  func testPickingThePriorFinancialYearDoesNotFollowToday() {
    let now = date(2026, 11, 15)
    XCTAssertFalse(
      PeriodAnchorPolicy.followsToday(afterPicking: date(2025, 11, 15), basis: .financialYear, now: now, calendar: utc)
    )
  }

  func testRefreshWhileFollowingTodayTakesTheNewNow() {
    let current = date(2026, 11, 15)
    let now = date(2026, 11, 16, hour: 0)
    XCTAssertEqual(
      PeriodAnchorPolicy.anchorAfterRefresh(current: current, followsToday: true, now: now),
      now
    )
  }

  func testRefreshWhilePinnedKeepsThePickedAnchor() {
    let picked = date(2026, 10, 15)
    let now = date(2026, 11, 16, hour: 0)
    XCTAssertEqual(
      PeriodAnchorPolicy.anchorAfterRefresh(current: picked, followsToday: false, now: now),
      picked
    )
  }
}
