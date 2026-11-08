import NomiCore
import SwiftUI
import XCTest
@testable import NomiUI

final class DesignTokenTests: XCTestCase {
  func testSurfaceStepsMatchTheApprovedLightScale() {
    let environment = EnvironmentValues()
    // Light navy-ocean surfaces (F1 of nomi-ios-build-plan, I-1). Secondary
    // fill -> #EDF1F8.
    let steps: [(Color, UInt32)] = [
      (NomiColor.surface, 0xEDF1F8),
    ]
    for (actual, hex) in steps {
      assertResolves(actual, toHex: hex, environment: environment)
    }
  }

  func testNamedColourTokensResolveToTheirHexValues() {
    let environment = EnvironmentValues()
    let tokens: [(Color, UInt32)] = [
      (NomiColor.ground, 0xF3F6FB),
      (NomiColor.card, 0xFFFFFF),
      (NomiColor.ink, 0x0E1424),
      (NomiColor.inkDeep, 0x0A2150),
      (NomiColor.inkSecondary, 0x53607A),
      (NomiColor.inkTab, 0x3A4660),
      (NomiColor.navy, 0x023571),
      (NomiColor.navyDeep, 0x04174B),
      (NomiColor.track, 0xDCE8F5),
      (NomiColor.primary, 0x06080F),
      (NomiColor.error, 0xB42318),
      (NomiColor.errorTint, 0xFDECEA),
      (NomiColor.switchOff, 0xC5CEDE),
      (NomiColor.heroGlassSolid, 0x0E3972),
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

  func testScreenGutterIsTwentyAcrossEveryArtboard() {
    XCTAssertEqual(NomiSpacing.screenGutter, 20)
  }

  func testRadiusFloorIsRespectedForNamedTokens() {
    XCTAssertGreaterThanOrEqual(NomiRadius.tile, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.card, 8)
    XCTAssertGreaterThanOrEqual(NomiRadius.sheet, 8)
  }

  func testCardRadiusIsTwentyFourAndInsetIsSixteen() {
    // Concentric: card 24 -> inset 16 -> tile 8.
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
