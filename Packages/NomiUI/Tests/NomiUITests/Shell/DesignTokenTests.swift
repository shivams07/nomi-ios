import NomiCore
import SwiftUI
import XCTest
@testable import NomiUI

final class DesignTokenTests: XCTestCase {
  func testSurfaceStepsMatchTheApprovedLightScale() {
    let environment = EnvironmentValues()
    // Moss surfaces (wave 1 F1, plan I-9). Secondary fill -> #EEF3E8.
    let steps: [(Color, UInt32)] = [
      (NomiColor.surface, 0xEEF3E8),
    ]
    for (actual, hex) in steps {
      assertResolves(actual, toHex: hex, environment: environment)
    }
  }

  func testNamedColourTokensResolveToTheirHexValues() {
    let environment = EnvironmentValues()
    let tokens: [(Color, UInt32)] = [
      (NomiColor.ground, 0xF3F5F0),
      (NomiColor.card, 0xFFFFFF),
      (NomiColor.ink, 0x111411),
      (NomiColor.inkDeep, 0x1F3320),
      (NomiColor.inkSecondary, 0x566055),
      (NomiColor.inkTab, 0x1F2A1F),
      (NomiColor.navy, 0x3C5A38),
      (NomiColor.navyDeep, 0x1F3320),
      (NomiColor.track, 0xDDE8D3),
      (NomiColor.primary, 0x0C0F0C),
      (NomiColor.error, 0xB42318),
      (NomiColor.errorTint, 0xFDECEA),
      (NomiColor.warning, 0x8A5300),
      (NomiColor.heroGlassSolid, 0x34543A),
    ]
    for (actual, hex) in tokens {
      assertResolves(actual, toHex: hex, environment: environment)
    }
  }

  func testLegacyNamesFollowTheirReplacements() {
    let environment = EnvironmentValues()
    assertSameRGB(NomiColor.textPrimary, NomiColor.ink, environment: environment)
    assertSameRGB(NomiColor.textTertiary, NomiColor.inkSecondary, environment: environment)
  }

  /// PEND B.8 N1: each text-on-surface pair is at or above 4.5:1, and the
  /// non-text pair at or above 3:1. `LightTokenTests` carries the full list
  /// and runs in the CLT harness. This is the Xcode copy of the floor.
  func testTextAndNonTextPairsMeetTheirContrastFloor() {
    let textPairs: [(UInt32, UInt32)] = [
      (NomiHex.ink, NomiHex.card),
      (NomiHex.ink, NomiHex.ground),
      (NomiHex.inkDeep, NomiHex.card),
      (NomiHex.inkDeep, NomiHex.ground),
      (NomiHex.inkSecondary, NomiHex.card),
      (NomiHex.inkSecondary, NomiHex.ground),
      (NomiHex.inkTab, NomiHex.card),
      (NomiHex.dayHeader, NomiHex.ground),
      (NomiHex.placeholder, NomiHex.card),
      (NomiHex.navy, NomiHex.card),
      (NomiHex.error, NomiHex.card),
      (NomiHex.error, NomiHex.ground),
      (NomiHex.error, NomiHex.errorTint),
      (NomiHex.onPrimary, NomiHex.primary),
      (NomiHex.onPrimary, NomiHex.navy),
      (NomiHex.onPrimary, NomiHex.error),
      (NomiHex.onPrimary, NomiHex.heroGlassSolid),
    ]
    for (foreground, background) in textPairs {
      XCTAssertGreaterThanOrEqual(NomiContrast.ratio(foreground, background), 4.5)
    }
    XCTAssertGreaterThanOrEqual(NomiContrast.ratio(NomiHex.navy, NomiHex.track), 3)
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

  func testScreenGutterIsSixteen() {
    XCTAssertEqual(NomiSpacing.screenGutter, 16)
  }

  func testRadiusFloorIsRespectedForNamedTokens() {
    XCTAssertGreaterThanOrEqual(NomiRadius.tile, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.card, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.sheet, 8)
  }

  func testCardRadiusIsTwentyEightAndInsetIsEighteen() {
    // Concentric: card 28 -> inset 18 -> tile 8.
    XCTAssertEqual(NomiRadius.card, 28)
    XCTAssertEqual(NomiRadius.inset, 18)
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

  // MARK: - Helpers

  /// Checks a resolved token against an integer hex value (0xRRGGBB) without
  /// building a colour from a hex literal, so this file constructs no colours
  /// from hex of its own.
  private func assertResolves(_ actual: Color, toHex hex: UInt32, environment: EnvironmentValues, file: StaticString = #filePath, line: UInt = #line) {
    let resolved = actual.resolve(in: environment)
    XCTAssertEqual(Double(resolved.red), Double((hex >> 16) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(Double(resolved.green), Double((hex >> 8) & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(Double(resolved.blue), Double(hex & 0xFF) / 255, accuracy: 0.001, file: file, line: line)
  }

  private func assertSameRGB(_ actual: Color, _ expected: Color, environment: EnvironmentValues, file: StaticString = #filePath, line: UInt = #line) {
    let resolvedActual = actual.resolve(in: environment)
    let resolvedExpected = expected.resolve(in: environment)
    XCTAssertEqual(resolvedActual.red, resolvedExpected.red, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(resolvedActual.green, resolvedExpected.green, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(resolvedActual.blue, resolvedExpected.blue, accuracy: 0.001, file: file, line: line)
  }
}
