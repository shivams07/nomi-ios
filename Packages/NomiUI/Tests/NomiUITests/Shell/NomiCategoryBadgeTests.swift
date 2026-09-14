import SwiftUI
import XCTest
@testable import NomiUI

final class NomiCategoryBadgeTests: XCTestCase {
  func testNilSlotFallsBackToOther() {
    let badge = NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 40)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.other)
  }

  func testOutOfRangeSlotFallsBackToOther() {
    let badge = NomiCategoryBadge(symbolName: "questionmark", paletteSlot: 99, size: 40)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.other)
  }

  func testValidSlotResolvesToItsPaletteHue() {
    let badge = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 40)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.slots[0])
  }
}
