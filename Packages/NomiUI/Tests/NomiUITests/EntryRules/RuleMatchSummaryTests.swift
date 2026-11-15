import XCTest
@testable import NomiUI

/// The match count goes through the catalog's plural variations (F6b, S10), so
/// 0, 1 and 2 must each read correctly.
final class RuleMatchSummaryTests: XCTestCase {
  func testZeroMatchesText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 0), "0 rows match")
  }

  func testSingularMatchText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 1), "1 row matches")
  }

  func testPluralMatchText() {
    XCTAssertEqual(RuleMatchSummary.text(for: 12), "12 rows match")
  }
}
