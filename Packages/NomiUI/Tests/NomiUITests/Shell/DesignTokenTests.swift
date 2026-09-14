import NomiCore
import SwiftUI
import XCTest
@testable import NomiUI

final class DesignTokenTests: XCTestCase {
  func testFiveOpaqueSurfaceStepsMatchTheDesignScale() {
    let environment = EnvironmentValues()
    // v5 (`nomi-ui-refresh`) hexes. Pinning these against the production
    // tokens before this unit's change is exactly how a run of this test
    // would go red first (the gate this done-when asks for) — the old
    // production values (`#0c0c0c`, `#292929`, `#212121`, `#1C1C1C`,
    // `#1E1E1E`) fail these five assertions until NomiColor.swift moves too.
    let steps: [(Color, UInt32)] = [
      (NomiColor.surfaceCanvas, 0x0A0E17),
      (NomiColor.surface, 0x262C3A),
      (NomiColor.surfaceRaised, 0x1C2130),
      (NomiColor.surfaceRow, 0x151A25),
      (NomiColor.surfaceInput, 0x1A1F2B),
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

  func testCardRadiusIsTwentyFourAndInsetIsSixteen() {
    // v5: card 16 -> 24, restoring the v4 ruling that never shipped; new
    // `inset` step for tiles inside a card. Concentric: card 24 -> inset 16 -> tile 8.
    XCTAssertEqual(NomiRadius.card, 24)
    XCTAssertEqual(NomiRadius.inset, 16)
    XCTAssertEqual(NomiRadius.tile, 8)
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
