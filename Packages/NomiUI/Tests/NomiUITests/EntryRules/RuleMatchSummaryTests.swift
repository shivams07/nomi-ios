import XCTest
@testable import NomiUI

final class RuleMatchSummaryTests: XCTestCase {
  func testZeroMatchesText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 0), "Matches 0 transactions")
  }

  func testSingularMatchText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 1), "Matches 1 transaction")
  }

  func testPluralMatchText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 12), "Matches 12 transactions")
  }
}
