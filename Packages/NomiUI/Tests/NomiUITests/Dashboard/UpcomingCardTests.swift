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

  /// X1. The row's second line is "<verb> 12 Nov · monthly", the verb from S7's
  /// `RecurringCopy.verb` on the category name: "Due" for a bill, "Next" with no
  /// category. The fixture is built in the India calendar `UpcomingRows` reads days in,
  /// so the date is zone-safe.
  func testRowSubtitleNamesTheVerbDateAndCadence() {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 12
    components.hour = 12
    let renewal = NomiCalendar.india.date(from: components)!
    let uncategorised = RecurringSeries(
      id: "NETFLIX",
      label: "Netflix",
      amountMinor: 64900,
      occurrences: 3,
      lastDate: Date(timeIntervalSinceNow: -30 * 86_400),
      nextExpected: renewal
    )
    let bill = RecurringSeries(
      id: "ELECTRIC",
      label: "Power",
      amountMinor: 1_200_00,
      occurrences: 3,
      lastDate: Date(timeIntervalSinceNow: -30 * 86_400),
      nextExpected: renewal,
      category: CategoryBadge(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
        name: "Bills & Utilities",
        symbolName: "bolt",
        paletteSlot: 3
      )
    )

    XCTAssertEqual(UpcomingRows.subtitle(for: uncategorised), "Next 12 Nov · monthly")
    XCTAssertEqual(UpcomingRows.subtitle(for: bill), "Due 12 Nov · monthly")
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
