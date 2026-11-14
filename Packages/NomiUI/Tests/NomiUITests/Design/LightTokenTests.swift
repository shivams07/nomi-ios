// clt-harness: include
import SwiftUI
import Testing
@testable import NomiUI

/// The light token gates (F1 of nomi-ios-build-plan, I-1 to I-3). They run on
/// `NomiHex` integers and `NomiContrast`, so they need no rendering. They also
/// run in the CLT harness (V2), not only in Xcode.
@Suite("Light tokens")
struct LightTokenTests {
  // MARK: - Contrast

  @Test func textPairsPassAA() {
    let pairs: [(String, UInt32, UInt32)] = [
      ("ink on card", NomiHex.ink, NomiHex.card),
      ("ink on ground", NomiHex.ink, NomiHex.ground),
      ("inkDeep on card", NomiHex.inkDeep, NomiHex.card),
      ("inkDeep on ground", NomiHex.inkDeep, NomiHex.ground),
      ("inkSecondary on card", NomiHex.inkSecondary, NomiHex.card),
      ("inkSecondary on ground", NomiHex.inkSecondary, NomiHex.ground),
      ("inkTab on card", NomiHex.inkTab, NomiHex.card),
      ("inkTab on ground", NomiHex.inkTab, NomiHex.ground),
      ("dayHeader on ground", NomiHex.dayHeader, NomiHex.ground),
      ("placeholder on card", NomiHex.placeholder, NomiHex.card),
      ("placeholder on ground", NomiHex.placeholder, NomiHex.ground),
      ("navy on card", NomiHex.navy, NomiHex.card),
      ("navy on ground", NomiHex.navy, NomiHex.ground),
      ("error on card", NomiHex.error, NomiHex.card),
      ("error on ground", NomiHex.error, NomiHex.ground),
      ("error on errorTint", NomiHex.error, NomiHex.errorTint),
      ("onPrimary on primary", NomiHex.onPrimary, NomiHex.primary),
      ("onPrimary on navy", NomiHex.onPrimary, NomiHex.navy),
      ("onPrimary on error", NomiHex.onPrimary, NomiHex.error),
      ("onPrimary on heroGlassSolid", NomiHex.onPrimary, NomiHex.heroGlassSolid),
      ("warning on card", NomiHex.warning, NomiHex.card),
      ("warning on warningTint", NomiHex.warning, NomiHex.warningTint),
    ]
    for (name, foreground, background) in pairs {
      let ratio = NomiContrast.ratio(foreground, background)
      #expect(ratio >= 4.5, "\(name) is \(ratio), below 4.5:1")
    }
  }

  @Test func nonTextPairsPassThreeToOne() {
    #expect(NomiContrast.ratio(NomiHex.navy, NomiHex.track) >= 3)
  }

  @Test func decimalsPassAAOnCardAndGround() {
    #expect(NomiColor.decimalOpacityGround == 0.65)
    let onCard = NomiContrast.blend(NomiHex.ink, over: NomiHex.card, alpha: NomiColor.decimalOpacityGround)
    let onGround = NomiContrast.blend(NomiHex.ink, over: NomiHex.ground, alpha: NomiColor.decimalOpacityGround)
    #expect(NomiContrast.ratio(onCard, NomiHex.card) >= 4.5)
    #expect(NomiContrast.ratio(onGround, NomiHex.ground) >= 4.5)
  }

  @Test func knownRatiosMatchTheSpec() {
    // Moss column of plan I-9, checked by the wave 1 F1 contrast figures.
    #expect(abs(NomiContrast.ratio(NomiHex.error, NomiHex.card) - 6.57) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.inkSecondary, NomiHex.ground) - 5.98) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.navy, NomiHex.track) - 6.11) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.ink, NomiHex.card) - 18.55) < 0.01)
  }

  @Test func contrastHelperMatchesWCAGReferencePoints() {
    #expect(abs(NomiContrast.ratio(0xFFFFFF, 0x000000) - 21) < 0.001)
    #expect(abs(NomiContrast.ratio(0xFFFFFF, 0xFFFFFF) - 1) < 0.001)
    #expect(NomiContrast.blend(0x0E1424, over: 0xFFFFFF, alpha: 0.65) == 0x626671)
    #expect(NomiContrast.blend(0xFFFFFF, over: 0x000000, alpha: 1) == 0xFFFFFF)
  }

  // MARK: - Hex values (I-1)

  @Test func colourHexesArePinned() {
    let pinned: [(String, UInt32, UInt32)] = [
      ("ground", NomiHex.ground, 0xF3F5F0),
      ("card", NomiHex.card, 0xFFFFFF),
      ("ink", NomiHex.ink, 0x111411),
      ("inkDeep", NomiHex.inkDeep, 0x1F3320),
      ("inkSecondary", NomiHex.inkSecondary, 0x566055),
      ("inkTab", NomiHex.inkTab, 0x1F2A1F),
      ("dayHeader", NomiHex.dayHeader, 0x3C5A38),
      ("placeholder", NomiHex.placeholder, 0x566055),
      ("navy", NomiHex.navy, 0x3C5A38),
      ("navyDeep", NomiHex.navyDeep, 0x1F3320),
      ("blueMid", NomiHex.blueMid, 0x6B8E5E),
      ("track", NomiHex.track, 0xDDE8D3),
      ("iconTile", NomiHex.iconTile, 0xEEF3E8),
      ("iconGlyph", NomiHex.iconGlyph, 0x3C5A38),
      ("primary", NomiHex.primary, 0x0C0F0C),
      ("onPrimary", NomiHex.onPrimary, 0xFFFFFF),
      ("error", NomiHex.error, 0xB42318),
      ("errorTint", NomiHex.errorTint, 0xFDECEA),
      ("warning", NomiHex.warning, 0x8A5300),
      ("warningFill", NomiHex.warningFill, 0xD99A1F),
      ("warningTint", NomiHex.warningTint, 0xFBF0DA),
      ("heroGlassSolid", NomiHex.heroGlassSolid, 0x34543A),
      ("heroGlassTint", NomiHex.heroGlassTint, 0x1F3320),
      ("secondaryFill", NomiHex.secondaryFill, 0xEEF3E8),
    ]
    for (name, actual, expected) in pinned {
      #expect(actual == expected, "\(name) is \(String(actual, radix: 16)), expected \(String(expected, radix: 16))")
    }
  }

  @Test func insightsSliceTintsArePinnedWithTheirContrast() {
    // IN, decisions Amendment 2 R3: the artboard's third and fourth donut slices.
    #expect(NomiHex.chartTintMid == 0xA9C39B)
    #expect(NomiHex.chartTintLight == 0xDDE8D3)
    #expect(abs(NomiContrast.ratio(NomiHex.chartTintMid, NomiHex.card) - 1.91) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.chartTintLight, NomiHex.card) - 1.27) < 0.01)
  }

  @Test func heroRampHexesArePinned() {
    #expect(NomiHex.heroRamp0 == 0x1E3325)
    #expect(NomiHex.heroRamp1 == 0x34543A)
    #expect(NomiHex.heroRamp2 == 0x5F8558)
    #expect(NomiHex.heroRamp3 == 0xA9C39B)
    #expect(NomiHex.heroRamp4 == 0xD9E5CF)
  }

  // MARK: - Hero text floors (plan I-9, Risks 1)

  /// The hero colour at artboard `y`, read from the stops the gradient draws.
  /// `stops(height:)` ends with the colour at its height.
  private func heroHex(atY y: Int) -> UInt32 {
    guard y > 0 else { return NomiHex.heroRamp0 }
    return NomiHeroGradient.stops(height: CGFloat(y), safeTop: NomiHeroGradient.artboardSafeTop).last?.hex ?? NomiHex.heroRamp0
  }

  @Test func heroTextFloorsAreTight() {
    // White text passes 4.5:1 through y 299 and fails from y 300.
    for y in 0...299 {
      let ratio = NomiContrast.ratio(NomiHex.white, heroHex(atY: y))
      #expect(ratio >= 4.5, "white on the hero at y \(y) is \(ratio)")
    }
    #expect(NomiContrast.ratio(NomiHex.white, heroHex(atY: 300)) < 4.5)
    #expect(NomiHeroGradient.whiteTextFloor == 299)
    // moss900 text passes 4.5:1 from y 361 to the bottom of the 504 pt hero and fails at 360.
    for y in 361...504 {
      let ratio = NomiContrast.ratio(NomiHex.navyDeep, heroHex(atY: y))
      #expect(ratio >= 4.5, "navyDeep on the hero at y \(y) is \(ratio)")
    }
    #expect(NomiContrast.ratio(NomiHex.navyDeep, heroHex(atY: 360)) < 4.5)
    #expect(NomiHeroGradient.darkTextCeiling == 361)
  }

  @Test func heroTextSecondaryPassesToY264() {
    // heroTextSecondary is white at 90%. Read the opacity from the token itself.
    let token = NomiColor.heroTextSecondary.resolve(in: EnvironmentValues())
    #expect(abs(Double(token.opacity) - 0.90) < 1e-4, "heroTextSecondary opacity is \(token.opacity), expected 0.90")
    for y in 0...264 {
      let background = heroHex(atY: y)
      let text = NomiContrast.blend(NomiHex.white, over: background, alpha: 0.90)
      let ratio = NomiContrast.ratio(text, background)
      #expect(ratio >= 4.5, "white 90% on the hero at y \(y) is \(ratio)")
    }
  }

  // MARK: - Warning (plan I-9)

  @Test func warningTextPasses() {
    #expect(NomiContrast.ratio(NomiHex.warning, NomiHex.card) >= 4.5)
    #expect(NomiContrast.ratio(NomiHex.warning, NomiHex.warningTint) >= 4.5)
  }

  @Test func oneErrorRedAndNoCategoryRed() {
    // SIMP §5: one error red, `#B42318`. The retired over-budget red is not
    // used for error or over-budget meaning anywhere in the token set.
    #expect(NomiHex.error == 0xB42318)
    #expect(NomiHex.error != 0xE66767)
  }

  // MARK: - Radius, spacing, shadow and type (I-2, I-3)

  @Test func radiusScaleValues() {
    #expect(NomiRadius.tile == 8)
    #expect(NomiRadius.inset == 18)
    #expect(NomiRadius.card == 28)
    #expect(NomiRadius.sheet == 32)
    #expect(NomiRadius.chip == 18)
    #expect(NomiRadius.control == 22)
  }

  @Test func spacingLayoutValues() {
    #expect(NomiSpacing.screenGutter == 16)
    #expect(NomiSpacing.tabBarSideMargin == 24)
    #expect(NomiSpacing.tabBarBottomMargin == 22)
    #expect(NomiSpacing.minTarget == 44)
    #expect(NomiSpacing.navRowHeight == 44)
    #expect(NomiSpacing.cardGap == 12)
    #expect(NomiSpacing.heroSheetOverlap == 24)
    #expect(NomiSpacing.rowMinHeight == 52)
  }

  @Test func shadowValues() {
    #expect(NomiShadow.card.radius == 11)
    #expect(NomiShadow.card.y == 8)
    #expect(NomiShadow.tabBar.radius == 16)
    #expect(NomiShadow.tabBar.y == 12)
    #expect(NomiShadow.plus.radius == 9)
    #expect(NomiShadow.heroSheet.y == -6)
  }

  @Test func interFaceNamesAreDefined() {
    #expect(NomiFont.interRegular == "Inter-Regular")
    #expect(NomiFont.interMedium == "Inter-Medium")
    #expect(NomiFont.interSemiBold == "Inter-SemiBold")
  }

  @Test func bundledFontsAreTheThreeInterFilesPresentInTheRepo() {
    #expect(NomiFont.bundledFileNames.count == 3)
    #expect(NomiFont.bundledFileNames.contains("Inter-Regular.otf"))
  }

  @Test func trackingValuesFromTheTypeTable() {
    #expect(NomiTextStyle.largeTitle.tracking == -0.4)
    #expect(NomiTextStyle.heroAmount.tracking == -1.4)
    #expect(NomiTextStyle.displayValue.tracking == -0.6)
    #expect(NomiTextStyle.summaryValue.tracking == -0.4)
    #expect(NomiTextStyle.body.tracking == 0)
  }

  @Test func everyI1NameIsDeclared() {
    // Compiles only if each I-1 colour token exists. Values are pinned above
    // through `NomiHex`, and in `DesignTokenTests` through resolved `Color`s.
    let names: [Any] = [
      NomiColor.ground, NomiColor.card, NomiColor.ink, NomiColor.inkDeep,
      NomiColor.inkSecondary, NomiColor.inkTab, NomiColor.dayHeader, NomiColor.placeholder,
      NomiColor.navy, NomiColor.navyDeep, NomiColor.blueMid, NomiColor.track,
      NomiColor.iconTile, NomiColor.iconGlyph, NomiColor.primary, NomiColor.onPrimary,
      NomiColor.error, NomiColor.errorTint, NomiColor.warning, NomiColor.warningFill,
      NomiColor.warningTint, NomiColor.chartMuted, NomiColor.chartHighlight, NomiColor.separator,
      NomiColor.heroText, NomiColor.heroTextSecondary, NomiColor.heroGlassFill,
      NomiColor.heroGlassBorder, NomiColor.heroGlassHighlight, NomiColor.heroGlassSolid,
      NomiColor.tabGlassTop, NomiColor.tabGlassBottom, NomiColor.tabGlassBorder,
    ]
    #expect(names.count == 33)
  }
}
