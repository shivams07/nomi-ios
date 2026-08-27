import Foundation
import XCTest
@testable import NomiUI

final class RulesReorderTests: XCTestCase {
  private let ids = (0..<4).map { _ in UUID() }

  func testMovingFirstToLast() {
    let result = RulesReorder.orderedIDs(current: ids, from: IndexSet(integer: 0), to: 4)
    XCTAssertEqual(result, [ids[1], ids[2], ids[3], ids[0]])
  }

  func testMovingLastToFirst() {
    let result = RulesReorder.orderedIDs(current: ids, from: IndexSet(integer: 3), to: 0)
    XCTAssertEqual(result, [ids[3], ids[0], ids[1], ids[2]])
  }

  func testNoOpWhenDestinationMatchesSource() {
    let result = RulesReorder.orderedIDs(current: ids, from: IndexSet(integer: 1), to: 1)
    XCTAssertEqual(result, ids)
  }
}
