import NomiCore
import XCTest

@testable import NomiUI

/// U17b. `RecurringSeries` is a plain `Sendable` struct, not an `@Model` —
/// unlike `Transaction` elsewhere in this file's neighbours, there is no
/// crash risk in constructing it directly here, so `UpcomingRows.soonest`
/// (the pure sort-and-cap `UpcomingCard.body` delegates to, same shape as
/// `RecentRows.mostRecent`) is tested straightforwardly.
final class UpcomingCardTests: XCTestCase {

  func testCapsAtFiveEvenWithMoreSeriesAvailable() {
    let allSeries = (0..<8).map { makeSeries(id: "S\($0)", daysFromNow: $0) }

    XCTAssertEqual(UpcomingRows.soonest(allSeries).count, 5)
  }

  func testOrdersByNextExpectedAscendingRegardlessOfInputOrder() {
    let soon = makeSeries(id: "SOON", daysFromNow: 1)
    let soonest = makeSeries(id: "SOONEST", daysFromNow: 0)
    let later = makeSeries(id: "LATER", daysFromNow: 10)
    let latest = makeSeries(id: "LATEST", daysFromNow: 20)

    let result = UpcomingRows.soonest([later, latest, soon, soonest])

    XCTAssertEqual(result.map { $0.id }, ["SOONEST", "SOON", "LATER", "LATEST"])
  }

  func testCapKeepsTheFiveSoonestNotTheFirstFiveInInputOrder() {
    // Deliberately fed latest-first, so a cap that truncated before sorting
    // would keep the wrong five.
    let allSeries = (0..<8).map { makeSeries(id: "S\($0)", daysFromNow: 7 - $0) }

    let result = UpcomingRows.soonest(allSeries)

    XCTAssertEqual(result.map { $0.id }, ["S7", "S6", "S5", "S4", "S3"])
  }

  func testEmptyInputProducesEmptyOutput() {
    XCTAssertTrue(UpcomingRows.soonest([]).isEmpty)
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
