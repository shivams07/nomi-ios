import XCTest
@testable import NomiUI

final class EntrySaveGateTests: XCTestCase {
  func testZeroAmountBlocksSave() {
    XCTAssertFalse(EntrySaveGate.isEnabled(amountMinor: 0))
  }

  func testNegativeAmountBlocksSave() {
    XCTAssertFalse(EntrySaveGate.isEnabled(amountMinor: -100))
  }

  func testPositiveAmountEnablesSave() {
    XCTAssertTrue(EntrySaveGate.isEnabled(amountMinor: 1))
  }
}
