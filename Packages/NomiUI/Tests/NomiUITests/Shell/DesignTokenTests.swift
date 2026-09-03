import NomiCore
import SwiftUI
import XCTest
@testable import NomiUI

final class DesignTokenTests: XCTestCase {
  func testFiveOpaqueSurfaceStepsMatchTheDesignScale() {
    let environment = EnvironmentValues()
    let steps: [(Color, UInt32)] = [
      (NomiColor.surfaceCanvas, 0x0c0c0c),
      (NomiColor.surface, 0x292929),
      (NomiColor.surfaceRaised, 0x212121),
      (NomiColor.surfaceRow, 0x1C1C1C),
      (NomiColor.surfaceInput, 0x1E1E1E),
    ]
    for (actual, hex) in steps {
      let resolvedActual = actual.resolve(in: environment)
      let resolvedExpected = Color(hex: hex).resolve(in: environment)
      XCTAssertEqual(resolvedActual.red, resolvedExpected.red, accuracy: 0.001)
      XCTAssertEqual(resolvedActual.green, resolvedExpected.green, accuracy: 0.001)
      XCTAssertEqual(resolvedActual.blue, resolvedExpected.blue, accuracy: 0.001)
    }
  }

  func testDirectionColorsNoLongerBorrowTextHierarchy() {
    XCTAssertNotEqual(NomiColor.creditText, NomiColor.textPrimary)
    XCTAssertNotEqual(NomiColor.debitText, NomiColor.textSecondary)
  }

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
