import XCTest
@testable import NomiUI

final class RuleRowActionsTests: XCTestCase {
  func testSystemRuleOffersToggleNotDelete() {
    XCTAssertEqual(RuleRowActions.offered(isSystem: true), [.toggle])
  }

  func testUserRuleOffersBoth() {
    XCTAssertEqual(RuleRowActions.offered(isSystem: false), [.toggle, .delete])
  }
}

/// The built-in section's "Show all" preview (S10): three rows, then all of them.
final class RuleBuiltInPreviewTests: XCTestCase {
  private let rows = Array(0..<47)

  func testLimitIsThree() {
    XCTAssertEqual(RuleBuiltInPreview.rowLimit, 3)
  }

  func testCollapsedShowsTheFirstThreeRows() {
    XCTAssertEqual(RuleBuiltInPreview.visible(rows, showAll: false), [0, 1, 2])
  }

  func testShowAllShowsEveryRow() {
    XCTAssertEqual(RuleBuiltInPreview.visible(rows, showAll: true), rows)
  }

  func testFewerThanTheLimitShowsEveryRowCollapsed() {
    XCTAssertEqual(RuleBuiltInPreview.visible([0, 1], showAll: false), [0, 1])
  }

  func testExactlyTheLimitShowsEveryRowCollapsed() {
    XCTAssertEqual(RuleBuiltInPreview.visible([0, 1, 2], showAll: false), [0, 1, 2])
  }

  // "Show all" is offered only when collapsing hides something and no search is running.
  func testFourRowsCollapsedOffersShowAll() {
    XCTAssertTrue(RuleBuiltInPreview.offersShowAll(total: 4, showAll: false, searching: false))
  }

  func testThreeRowsCollapsedOffersNothing() {
    XCTAssertFalse(RuleBuiltInPreview.offersShowAll(total: 3, showAll: false, searching: false))
  }

  func testShowAllTappedOffersNothing() {
    XCTAssertFalse(RuleBuiltInPreview.offersShowAll(total: 47, showAll: true, searching: false))
  }

  func testSearchingOffersNothing() {
    XCTAssertFalse(RuleBuiltInPreview.offersShowAll(total: 47, showAll: false, searching: true))
  }
}

final class RuleRowSubtitleTests: XCTestCase {
  func testSystemRuleKeepsSystemTag() {
    XCTAssertEqual(RuleRowSubtitle.text(categoryName: "Food & Dining", isSystem: true), "Food & Dining · System")
  }

  func testUserRuleHasCategoryOnly() {
    XCTAssertEqual(RuleRowSubtitle.text(categoryName: "Transport", isSystem: false), "Transport")
  }
}
