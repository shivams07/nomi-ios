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

  /// A typed amount the rules refuse (three decimals, or one paisa over the cap)
  /// reads as zero, so it blocks Save. The gate sees the refused amount, not the
  /// text.
  func testARefusedTypedAmountBlocksSave() {
    XCTAssertFalse(EntrySaveGate.isEnabled(amountMinor: EntryAmount.minorUnits(from: "1.999")))
    XCTAssertFalse(EntrySaveGate.isEnabled(amountMinor: EntryAmount.minorUnits(from: "1000000000.01", locale: Locale(identifier: "en_IN"))))
    XCTAssertTrue(EntrySaveGate.isEnabled(amountMinor: EntryAmount.minorUnits(from: "1000000000", locale: Locale(identifier: "en_IN"))))
  }
}
