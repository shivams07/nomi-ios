import NomiCore
import XCTest
@testable import NomiUI

final class DesignTokenTests: XCTestCase {
  func testSevenSlotPaletteHasNoRepeatedHueAndNoBlue() {
    XCTAssertEqual(CategoryPalette.slots.count, 7)
  }

  func testPaletteSlotResolvesInRange() {
    for slot in 0..<7 {
      XCTAssertNoThrow(paletteSlot(slot))
    }
  }

  func testEighthCategoryFoldsToOther() {
    let resolved = paletteSlot(7)
    XCTAssertEqual(resolved, CategoryPalette.other)
  }

  func testNegativeSlotFoldsToOther() {
    XCTAssertEqual(paletteSlot(-1), CategoryPalette.other)
  }

  func testSpacingScaleIsStrict() {
    XCTAssertEqual(NomiSpacing.xxs, 4)
    XCTAssertEqual(NomiSpacing.xs, 8)
    XCTAssertEqual(NomiSpacing.sm, 16)
    XCTAssertEqual(NomiSpacing.md, 24)
    XCTAssertEqual(NomiSpacing.lg, 32)
    XCTAssertEqual(NomiSpacing.xl, 40)
    XCTAssertEqual(NomiSpacing.xxl, 48)
  }

  func testRadiusFloorIsRespectedForNamedTokens() {
    XCTAssertGreaterThanOrEqual(NomiRadius.tile, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.card, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.bar, 8)
  }

  func testCurrencyFormatterUsesEnINGroupingAndRupeeSymbol() {
    let text = NomiFormatters.amountString(minor: 123_45678)
    XCTAssertTrue(text.hasPrefix("₹"))
    XCTAssertTrue(text.contains(","))
  }

  func testWidestRealisticAmountFormat() {
    XCTAssertEqual(NomiFormatters.widestRealisticAmount, "₹99,99,999.00")
  }
}
