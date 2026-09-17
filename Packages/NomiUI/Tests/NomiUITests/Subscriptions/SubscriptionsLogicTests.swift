import NomiCore
import XCTest

@testable import NomiUI

/// M5. `RecurringSeries` is a plain `Sendable` struct, not an `@Model` — no
/// crash risk constructing it directly here, same reason `UpcomingCardTests`
/// next door does the same. Amounts mirror `FakeRecurringStore.sampleSeries`
/// (64900 Netflix, 11900 Spotify, 249900 Cult.fit) without importing
/// `NomiPreview`, which `NomiUITests` does not depend on.
final class SubscriptionsLogicTests: XCTestCase {

  func testMonthlyTotalSumsAllSeries() {
    let series = [
      makeSeries(id: "NETFLIX", label: "Netflix", amountMinor: 64900, daysFromNow: 3),
      makeSeries(id: "SPOTIFY INDIA", label: "Spotify", amountMinor: 11900, daysFromNow: 9),
      makeSeries(id: "CULT FIT MEMBERSHIP", label: "Cult.fit", amountMinor: 249900, daysFromNow: 16),
    ]

    XCTAssertEqual(SubscriptionsSummary.monthlyTotalMinor(series), 326_700)
  }

  func testMonthlyTotalIsZeroForEmptyInput() {
    XCTAssertEqual(SubscriptionsSummary.monthlyTotalMinor([]), 0)
  }

  func testNextIsTheSoonestRegardlessOfInputOrder() {
    let later = makeSeries(id: "LATER", label: "Later", amountMinor: 49900, daysFromNow: 10)
    let soonest = makeSeries(id: "SOONEST", label: "Soonest", amountMinor: 49900, daysFromNow: 0)

    XCTAssertEqual(SubscriptionsSummary.next([later, soonest])?.id, "SOONEST")
  }

  func testNextIsNilForEmptyInput() {
    XCTAssertNil(SubscriptionsSummary.next([]))
  }

  func testNextChargeThreeDaysOut() {
    let now = Date()
    let nextExpected = Calendar.current.date(byAdding: .day, value: 3, to: now)!

    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: nextExpected, now: now), "next in 3 days")
  }

  func testNextChargeToday() {
    let now = Date()

    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: now, now: now), "next today")
  }

  func testNextChargeTwoDaysOverdue() {
    let now = Date()
    let nextExpected = Calendar.current.date(byAdding: .day, value: -2, to: now)!

    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: nextExpected, now: now), "expected 2 days ago")
  }

  func testMonogramIsFirstLetterUppercased() {
    XCTAssertEqual(SubscriptionMonogram.letter("Netflix"), "N")
  }

  func testMonogramFallsBackToQuestionMarkForBlankLabel() {
    XCTAssertEqual(SubscriptionMonogram.letter(""), "?")
  }

  func testByExpectedDayGroupsPreservingSoonestFirstOrderAcrossAndWithinDays() {
    let sameDayFirst = makeSeries(id: "A", label: "A", amountMinor: 100, daysFromNow: 1)
    let sameDaySecond = makeSeries(id: "B", label: "B", amountMinor: 100, daysFromNow: 1)
    let laterDay = makeSeries(id: "C", label: "C", amountMinor: 100, daysFromNow: 5)

    let groups = SubscriptionsGrouping.byExpectedDay([sameDayFirst, sameDaySecond, laterDay])

    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].rows.map(\.id), ["A", "B"])
    XCTAssertEqual(groups[1].rows.map(\.id), ["C"])
  }

  func testByExpectedDayEmptyInputProducesNoGroups() {
    XCTAssertTrue(SubscriptionsGrouping.byExpectedDay([]).isEmpty)
  }

  // MARK: -

  private func makeSeries(id: String, label: String, amountMinor: Int, daysFromNow: Int) -> RecurringSeries {
    RecurringSeries(
      id: id,
      label: label,
      amountMinor: amountMinor,
      occurrences: 3,
      lastDate: Date(timeIntervalSinceNow: -30 * 86_400),
      nextExpected: Date(timeIntervalSinceNow: Double(daysFromNow) * 86_400)
    )
  }
}
