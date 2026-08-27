import XCTest
@testable import NomiUI

final class PaletteSlotOptionsTests: XCTestCase {
  /// Done-when (v5): "the category editor offers exactly seven slots and no
  /// arbitrary colour well."
  func testOffersExactlySevenSlots() {
    XCTAssertEqual(PaletteSlotOptions.all.count, 7)
  }

  func testSlotsAreZeroIndexedThroughSix() {
    XCTAssertEqual(PaletteSlotOptions.all, Array(0..<7))
  }
}
