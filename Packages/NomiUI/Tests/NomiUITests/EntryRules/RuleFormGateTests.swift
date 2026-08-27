import Foundation
import XCTest
@testable import NomiUI

final class RuleFormGateTests: XCTestCase {
  func testEmptyPatternIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "", categoryID: UUID()))
  }

  func testWhitespaceOnlyPatternIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "   ", categoryID: UUID()))
  }

  func testMissingCategoryIsInvalid() {
    XCTAssertFalse(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: nil))
  }

  func testPatternAndCategoryIsValid() {
    XCTAssertTrue(RuleFormGate.isValid(pattern: "*SWIGGY*", categoryID: UUID()))
  }
}
