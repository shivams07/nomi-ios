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

  func testNeutralStyleIgnoresSlot() {
    let slotted = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 32, style: .neutral)
    let unslotted = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: nil, size: 32, style: .neutral)
    XCTAssertEqual(slotted.resolvedFillForTesting, NomiColor.iconTile)
    XCTAssertEqual(unslotted.resolvedFillForTesting, NomiColor.iconTile)
    XCTAssertEqual(slotted.glyphColorForTesting, NomiColor.iconGlyph)
  }
}
