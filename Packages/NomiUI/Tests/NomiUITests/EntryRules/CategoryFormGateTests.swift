import XCTest
@testable import NomiUI

final class CategoryFormGateTests: XCTestCase {
  func testEmptyNameIsInvalid() {
    XCTAssertFalse(CategoryFormGate.isValid(name: ""))
  }

  func testWhitespaceOnlyNameIsInvalid() {
    XCTAssertFalse(CategoryFormGate.isValid(name: "   "))
  }

  func testNonEmptyNameIsValid() {
    XCTAssertTrue(CategoryFormGate.isValid(name: "Groceries"))
  }
}
