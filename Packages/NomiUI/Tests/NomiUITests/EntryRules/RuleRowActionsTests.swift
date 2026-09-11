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
