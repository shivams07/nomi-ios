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

final class RuleRowSubtitleTests: XCTestCase {
  func testSystemRuleKeepsSystemTag() {
    XCTAssertEqual(RuleRowSubtitle.text(categoryName: "Food & Dining", isSystem: true), "Food & Dining · System")
  }

  func testUserRuleHasCategoryOnly() {
    XCTAssertEqual(RuleRowSubtitle.text(categoryName: "Transport", isSystem: false), "Transport")
  }
}
