import CoreGraphics
import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// Pure-logic tests for the F3 components (nomi-ios-build-plan, I-4; A-09).
/// They run on hex integers and value types, so they need no rendering and
/// they run in the CLT harness (V2).
@Suite("F3 components")
struct NomiComponentsTests {
  // MARK: - Hero gradient stops

  @Test func heroStopsAtArtboardInset() {
    let stops = NomiHeroGradient.stops(height: 356, safeTop: 54)
    #expect(stops.map(\.hex) == [NomiHex.heroRamp0, NomiHex.heroRamp1, NomiHex.heroRamp2, 0x799B70])
    expectLocations(stops, [0, 171.0 / 356.0, 313.0 / 356.0, 1])
  }

  @Test func accountsHeroEndsAt4C6F4B() {
    let stops = NomiHeroGradient.stops(height: 250, safeTop: 54)
    #expect(stops.map(\.hex) == [NomiHex.heroRamp0, NomiHex.heroRamp1, 0x4C6F4B])
    expectLocations(stops, [0, 171.0 / 250.0, 1])
  }

  @Test func heroStopsShiftWithInset() {
    let stops = NomiHeroGradient.stops(height: 361, safeTop: 59)
    #expect(stops.map(\.hex) == [NomiHex.heroRamp0, NomiHex.heroRamp1, NomiHex.heroRamp2, 0x799B70])
    expectLocations(stops, [0, 176.0 / 361.0, 318.0 / 361.0, 1])
  }

  @Test func heroStopsNeverExceedOne() {
    for height in [CGFloat(120), 200, 250, 356, 361, 400, 844] {
      for safeTop in [CGFloat(47), 54, 59] {
        let stops = NomiHeroGradient.stops(height: height, safeTop: safeTop)
        #expect(stops.last?.location == 1)
        #expect(stops.allSatisfy { $0.location >= 0 && $0.location <= 1 })
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location < $1.location })
      }
    }
  }

  @Test func momentGradientEndpointsMatchBackfill() {
    #expect(NomiHeroGradient.momentHex(atFraction: 0) == NomiHex.heroRamp0)
    #expect(NomiHeroGradient.momentHex(atFraction: 0.45) == NomiHex.heroRamp1)
    #expect(NomiHeroGradient.momentHex(atFraction: 1) == NomiHex.heroRamp2)
  }

  // MARK: - Amount parts (I-4 NomiAmountFormat)

  @Test func amountPartsNegative() {
    #expect(
      NomiAmountFormat.parts(minor: -6_482_424)
        == NomiAmountParts(sign: "\u{2212}", integer: "₹64,824", decimals: ".24")
    )
  }

  @Test func amountPartsCreditPlus() {
    #expect(
      NomiAmountFormat.parts(minor: 3_850_000, showPlus: true)
        == NomiAmountParts(sign: "+", integer: "₹38,500", decimals: ".00")
    )
  }

  @Test func amountPartsZero() {
    #expect(
      NomiAmountFormat.parts(minor: 0)
        == NomiAmountParts(sign: "", integer: "₹0", decimals: ".00")
    )
  }

  @Test func amountPartsLakh() {
    #expect(
      NomiAmountFormat.parts(minor: 1_33_279_50)
        == NomiAmountParts(sign: "", integer: "₹1,33,279", decimals: ".50")
    )
  }

  @Test func amountPartsJPY() {
    #expect(NomiAmountFormat.parts(minor: 64_824, currencyCode: "JPY").decimals == "")
  }

  @Test func amountPlusIsOnlyForCredits() {
    #expect(NomiAmountFormat.parts(minor: -100, showPlus: true).sign == "\u{2212}")
    #expect(NomiAmountFormat.parts(minor: 100, showPlus: false).sign == "")
  }

  // MARK: - Hero button contrast (DEC-09, A-09 item 2)

  @Test func heroButtonContrast() {
    // Read the glass from the token itself, not from a copy of its value. The
    // The glass is heroGlassTint at 52% (fitted to the artboard, fidelity D3).
    // If heroGlassFill changes, this fails.
    let token = NomiColor.heroGlassFill.resolve(in: EnvironmentValues())
    #expect(abs(Double(token.opacity) - 0.52) < 1e-4, "heroGlassFill opacity is \(token.opacity), expected 0.52")
    #expect(abs(Double(token.red) - Double((NomiHex.heroGlassTint >> 16) & 0xFF) / 255) < 1e-4)
    #expect(abs(Double(token.green) - Double((NomiHex.heroGlassTint >> 8) & 0xFF) / 255) < 1e-4)
    #expect(abs(Double(token.blue) - Double(NomiHex.heroGlassTint & 0xFF) / 255) < 1e-4)
    let glassAlpha = Double(token.opacity)

    let cases: [(CGFloat, Double)] = [(520, 9.79), (844, 7.69)]
    for (y, expected) in cases {
      let background = NomiHeroGradient.momentHex(atFraction: y / 844)
      let glass = NomiContrast.blend(NomiHex.heroGlassTint, over: background, alpha: glassAlpha)
      let ratio = NomiContrast.ratio(NomiHex.white, glass)
      #expect(ratio >= 4.5, "white on glass at y \(y) is \(ratio)")
      #expect(abs(ratio - expected) <= 0.01, "white on glass at y \(y) is \(ratio), expected \(expected)")
    }
    let primary = NomiContrast.ratio(NomiHex.navyDeep, NomiHex.white)
    #expect(primary >= 4.5)
    #expect(abs(primary - 13.53) <= 0.01)
  }

  // MARK: - Hero button tokens (DEC-09, A-09 item 1)

  @Test func heroButtonStylePinsItsTokens() {
    #expect(NomiHeroButtonStyle.primaryFill == NomiColor.heroText)
    #expect(NomiHeroButtonStyle.primaryLabel == NomiColor.navyDeep)
    #expect(NomiHeroButtonStyle.secondaryFill == NomiColor.heroGlassFill)
    #expect(NomiHeroButtonStyle.secondaryBorder == NomiColor.heroGlassBorder)
  }

  // MARK: - Helpers

  private func expectLocations(_ stops: [NomiHeroStop], _ expected: [Double]) {
    #expect(stops.count == expected.count)
    for (stop, location) in zip(stops, expected) {
      #expect(abs(stop.location - location) < 1e-9)
    }
  }
}
