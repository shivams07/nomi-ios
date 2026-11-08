// clt-harness: include
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
    // SIMP §5 table and I-1 contrast column.
    #expect(abs(NomiContrast.ratio(NomiHex.error, NomiHex.card) - 6.57) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.inkSecondary, NomiHex.ground) - 5.84) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.navy, NomiHex.track) - 9.66) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.ink, NomiHex.card) - 18.35) < 0.01)
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
      ("ground", NomiHex.ground, 0xF3F6FB),
      ("card", NomiHex.card, 0xFFFFFF),
      ("ink", NomiHex.ink, 0x0E1424),
      ("inkDeep", NomiHex.inkDeep, 0x0A2150),
      ("inkSecondary", NomiHex.inkSecondary, 0x53607A),
      ("inkTab", NomiHex.inkTab, 0x3A4660),
      ("dayHeader", NomiHex.dayHeader, 0x3D5486),
      ("placeholder", NomiHex.placeholder, 0x5C6883),
      ("navy", NomiHex.navy, 0x023571),
      ("navyDeep", NomiHex.navyDeep, 0x04174B),
      ("blueMid", NomiHex.blueMid, 0x4F8AC4),
      ("track", NomiHex.track, 0xDCE8F5),
      ("iconTile", NomiHex.iconTile, 0xE3EDFB),
      ("iconGlyph", NomiHex.iconGlyph, 0x1B4290),
      ("primary", NomiHex.primary, 0x06080F),
      ("onPrimary", NomiHex.onPrimary, 0xFFFFFF),
      ("error", NomiHex.error, 0xB42318),
      ("errorTint", NomiHex.errorTint, 0xFDECEA),
      ("switchOff", NomiHex.switchOff, 0xC5CEDE),
      ("heroGlassSolid", NomiHex.heroGlassSolid, 0x0E3972),
      ("secondaryFill", NomiHex.secondaryFill, 0xEDF1F8),
    ]
    for (name, actual, expected) in pinned {
      #expect(actual == expected, "\(name) is \(String(actual, radix: 16)), expected \(String(expected, radix: 16))")
    }
  }

  @Test func insightsSliceTintsArePinnedWithTheirContrast() {
    // IN, decisions Amendment 2 R3: the artboard's third and fourth donut slices.
    #expect(NomiHex.chartTintMid == 0x8DB3EA)
    #expect(NomiHex.chartTintLight == 0xBBD3EE)
    #expect(abs(NomiContrast.ratio(NomiHex.chartTintMid, NomiHex.card) - 2.15) < 0.01)
    #expect(abs(NomiContrast.ratio(NomiHex.chartTintLight, NomiHex.card) - 1.54) < 0.01)
  }

  @Test func heroRampHexesArePinned() {
    #expect(NomiHex.navyDeep == 0x04174B)
    #expect(NomiHex.navy == 0x023571)
    #expect(NomiHex.blueMid == 0x4F8AC4)
    #expect(NomiHex.track == 0xDCE8F5)
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
    #expect(NomiRadius.inset == 16)
    #expect(NomiRadius.card == 24)
    #expect(NomiRadius.sheet == 32)
    #expect(NomiRadius.chip == 18)
    #expect(NomiRadius.control == 22)
  }

  @Test func spacingLayoutValues() {
    #expect(NomiSpacing.screenGutter == 20)
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

  @Test func bundledFontsAreTheFourFilesPresentInTheRepo() {
    #expect(NomiFont.bundledFileNames.count == 4)
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
      NomiColor.error, NomiColor.errorTint, NomiColor.switchOff, NomiColor.separator,
      NomiColor.scrim, NomiColor.heroText, NomiColor.heroTextSecondary, NomiColor.heroGlassFill,
      NomiColor.heroGlassBorder, NomiColor.heroGlassHighlight, NomiColor.heroGlassSolid,
      NomiColor.tabGlassTop, NomiColor.tabGlassBottom, NomiColor.tabGlassBorder,
    ]
    #expect(names.count == 30)
  }
}
