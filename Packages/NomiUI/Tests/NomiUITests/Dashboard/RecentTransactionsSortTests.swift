import Foundation
import XCTest
@testable import NomiUI

/// Exercises `RecentRows.mostRecent` against a plain stub, never a real
/// `Transaction`. Not because one cannot be built: a container constructs fine
/// under XCTest and only swift-testing traps (see `InMemoryModelContainer`'s
/// measured note in NomiCore). `DatedRow` exists so this algorithm can be
/// verified with no container, no schema and no store — which is a better test
/// of a sort than one needing all three.
private struct StubRow: DatedRow, Equatable {
  let label: String
  let date: Date
}

final class RecentTransactionsSortTests: XCTestCase {
  private func day(_ offset: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(offset * 86_400))
  }

  func testOrdersNewestFirst() {
    let rows = [
      StubRow(label: "old", date: day(1)),
      StubRow(label: "newest", date: day(3)),
      StubRow(label: "middle", date: day(2)),
    ]
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.map(\.label), ["newest", "middle", "old"])
  }

  func testLimitsToRequestedCount() {
    let rows = (0..<20).map { StubRow(label: "row-\($0)", date: day($0)) }
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.count, 5)
    XCTAssertEqual(result.first?.label, "row-19")
  }

  func testFewerRowsThanLimitReturnsAllOfThem() {
    let rows = (0..<3).map { StubRow(label: "row-\($0)", date: day($0)) }
    let result = RecentRows.mostRecent(rows, limit: 5)
    XCTAssertEqual(result.count, 3)
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertTrue(RecentRows.mostRecent([StubRow](), limit: 5).isEmpty)
  }
}
