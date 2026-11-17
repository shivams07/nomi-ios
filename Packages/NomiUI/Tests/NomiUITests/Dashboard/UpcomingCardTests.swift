import NomiCore
import XCTest

@testable import NomiUI

/// U17b. `RecurringSeries` is a plain `Sendable` struct, not an `@Model` —
/// unlike `Transaction` elsewhere in this file's neighbours, there is no
/// crash risk in constructing it directly here, so `UpcomingRows.soonest`
/// (the pure sort-and-cap `UpcomingCard.body` delegates to, same shape as
/// `RecentRows.mostRecent`) is tested straightforwardly.
final class UpcomingCardTests: XCTestCase {

  /// S1b step 5: Home shows at most two upcoming series.
  func testCapsAtTwoEvenWithMoreSeriesAvailable() {
    let allSeries = (0..<8).map { makeSeries(id: "S\($0)", daysFromNow: $0) }

    XCTAssertEqual(UpcomingRows.soonest(allSeries).count, 2)
  }

  func testOrdersByNextExpectedAscendingRegardlessOfInputOrder() {
    let soon = makeSeries(id: "SOON", daysFromNow: 1)
    let soonest = makeSeries(id: "SOONEST", daysFromNow: 0)
    let later = makeSeries(id: "LATER", daysFromNow: 10)
    let latest = makeSeries(id: "LATEST", daysFromNow: 20)

    let result = UpcomingRows.soonest([later, latest, soon, soonest])

    XCTAssertEqual(result.map { $0.id }, ["SOONEST", "SOON"])
  }

  func testCapKeepsTheTwoSoonestNotTheFirstTwoInInputOrder() {
    // Deliberately fed latest-first, so a cap that truncated before sorting
    // would keep the wrong two.
    let allSeries = (0..<8).map { makeSeries(id: "S\($0)", daysFromNow: 7 - $0) }

    let result = UpcomingRows.soonest(allSeries)

    XCTAssertEqual(result.map { $0.id }, ["S7", "S6"])
  }

  func testEmptyInputProducesEmptyOutput() {
    XCTAssertTrue(UpcomingRows.soonest([]).isEmpty)
  }

  /// M5. A series with no `category` (the detector's own default, and the
  /// third of `FakeRecurringStore.sampleSeries`) renders through the
  /// monogram path rather than `NomiCategoryBadge` — the pure rule
  /// `SubscriptionBadge.resolve` decides, shared with `SubscriptionsScreen`.
  func testSeriesWithoutCategoryRendersTheMonogramPath() {
    let series = makeSeries(id: "NOBADGE", daysFromNow: 2)

    XCTAssertEqual(SubscriptionBadge.resolve(series), .monogram("N"))
  }

  /// S1b step 5. Each row's second line is "Next 12 Nov · monthly". The Due or
  /// Renews verb arrives with X1. The day comes from the device calendar, the
  /// one `NomiFormatters.dayMonth` uses, so the date is zone-safe.
  func testRowSubtitleNamesTheNextDateAndCadence() {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 12
    components.hour = 12
    let renewal = Calendar.current.date(from: components)!
    let series = RecurringSeries(
      id: "NETFLIX",
      label: "Netflix",
      amountMinor: 64900,
      occurrences: 3,
      lastDate: Date(timeIntervalSinceNow: -30 * 86_400),
      nextExpected: renewal
    )

    XCTAssertEqual(UpcomingRows.subtitle(for: series), "Next 12 Nov · monthly")
  }

  // MARK: -

  private func makeSeries(id: String, daysFromNow: Int) -> RecurringSeries {
    RecurringSeries(
      id: id,
      label: id,
      amountMinor: 49900,
      occurrences: 3,
      lastDate: Date(timeIntervalSinceNow: -30 * 86_400),
      nextExpected: Date(timeIntervalSinceNow: Double(daysFromNow) * 86_400)
    )
  }
}
