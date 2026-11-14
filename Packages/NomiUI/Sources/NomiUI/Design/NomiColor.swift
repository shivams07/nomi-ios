// clt-harness: include
import SwiftUI

/// Nomi colour tokens: the Moss light system (wave 1 F1; plan I-9). Light only.
/// Every value comes from `NomiHex`.
///
/// Existing names keep compiling so every screen follows the new values
/// without being rewritten. Deprecated aliases are removed once no caller
/// remains. Legacy names still in use (`textPrimary`, `textTertiary`)
/// equal their replacement's value.
public enum NomiColor {
  // MARK: - Ground and surfaces

  /// Screen and sheet ground.
  public static let ground = Color(hex: NomiHex.ground)
  /// Cards, rows and inputs. Flat white, no glass.
  public static let card = Color(hex: NomiHex.card)
  /// Secondary fill. Legacy `surface`; no named replacement in I-1.
  public static let secondaryFill = Color(hex: NomiHex.secondaryFill)

  /// Legacy `surface`. Equals `secondaryFill`.
  public static let surface = Color(hex: NomiHex.secondaryFill)

  // MARK: - Text

  /// Primary text.
  public static let ink = Color(hex: NomiHex.ink)
  /// Section labels, credit amounts, day ticks.
  public static let inkDeep = Color(hex: NomiHex.inkDeep)
  /// Captions, subtitles, values. Legacy `textTertiary`.
  public static let inkSecondary = Color(hex: NomiHex.inkSecondary)
  /// Unselected tab icon and label.
  public static let inkTab = Color(hex: NomiHex.inkTab)
  /// Ledger day header.
  public static let dayHeader = Color(hex: NomiHex.dayHeader)
  /// Text-field placeholder.
  public static let placeholder = Color(hex: NomiHex.placeholder)

  /// Legacy `textPrimary`. Equals `ink`.
  public static let textPrimary = Color(hex: NomiHex.ink)
  /// Legacy `textTertiary`. Equals `inkSecondary`.
  public static let textTertiary = Color(hex: NomiHex.inkSecondary)

  // MARK: - Blue

  /// Back chevron, nav "+", links, switch on, selected chip and segment fill,
  /// chart marks, progress bar fill.
  public static let navy = Color(hex: NomiHex.navy)
  /// moss900. Text on the hero above `NomiHeroGradient.darkTextCeiling`.
  public static let navyDeep = Color(hex: NomiHex.navyDeep)
  /// moss500. Not a hero stop: the hero ramp uses `NomiHex.heroRamp0...4`.
  public static let blueMid = Color(hex: NomiHex.blueMid)
  /// Progress and ring track, hero tail.
  public static let track = Color(hex: NomiHex.track)
  /// Neutral row badge fill.
  public static let iconTile = Color(hex: NomiHex.iconTile)
  /// Neutral row badge glyph.
  public static let iconGlyph = Color(hex: NomiHex.iconGlyph)
  /// Insights donut slice 3 (artboard #8DB3EA). Chart fill only.
  public static let chartTintMid = Color(hex: NomiHex.chartTintMid)
  /// Insights donut slice 4 (moss100). Chart fill only.
  public static let chartTintLight = Color(hex: NomiHex.chartTintLight)
  /// Non-highlighted daily and monthly bars on the Insights card (moss500).
  /// Solid, not an alpha of `navy`, so the bars clear 3:1 on card and against
  /// `chartHighlight`. Chart fill only.
  public static let chartMuted = Color(hex: NomiHex.blueMid)
  /// The highlighted bar on the Insights card (moss900). Chart fill only.
  public static let chartHighlight = Color(hex: NomiHex.navyDeep)

  // MARK: - Controls

  /// The one black primary control and the selected tab capsule.
  public static let primary = Color(hex: NomiHex.primary)
  /// Text and glyphs on `primary`, `navy` and `error` fills.
  public static let onPrimary = Color(hex: NomiHex.onPrimary)

  // MARK: - Error

  /// The one error red (SIMP §5): error text, over-budget text and bar fill,
  /// destructive row text, the Backfill failure icon.
  public static let error = Color(hex: NomiHex.error)
  /// Error card and icon tile fill.
  public static let errorTint = Color(hex: NomiHex.errorTint)

  // MARK: - Warning

  /// Warning text: the "close to budget" tag and note text.
  public static let warning = Color(hex: NomiHex.warning)
  /// Close-to-budget bar fill. Non-text: always paired with the `warning` tag.
  public static let warningFill = Color(hex: NomiHex.warningFill)
  /// Warning tag and note ground.
  public static let warningTint = Color(hex: NomiHex.warningTint)

  // MARK: - Separators

  /// Card hairline and row divider: deep ink at 8%.
  public static let separator = Color(hex: NomiHex.inkDeep, opacity: 0.08)

  // MARK: - Decimals (SIMP §1 rule 4)

  /// Amount decimals on the white ground: ink at 65% (5.74:1 on card).
  public static let decimalOpacityGround: Double = 0.65
  /// Amount decimals on the hero: white at 60%.
  public static let decimalOpacityHero: Double = 0.60

  // MARK: - Hero (white text to artboard y 299, white 90% to y 264; see NomiHeroGradient)

  public static let heroText = Color(hex: NomiHex.white)
  /// White at 90%. At or above 4.5:1 on the ramp for y ≤ 264 (plan I-9).
  public static let heroTextSecondary = Color(hex: NomiHex.white, opacity: 0.90)
  /// Dark glass on the hero: `heroGlassTint` at 52%, fitted to the artboard
  /// (see `NomiHex.heroGlassTint`).
  public static let heroGlassFill = Color(hex: NomiHex.heroGlassTint, opacity: 0.52)
  public static let heroGlassBorder = Color(hex: NomiHex.white, opacity: 0.40)
  public static let heroGlassHighlight = Color(hex: NomiHex.white, opacity: 0.22)
  /// Reduce Transparency fallback for the hero glass.
  public static let heroGlassSolid = Color(hex: NomiHex.heroGlassSolid)

  // MARK: - Tab bar glass

  public static let tabGlassTop = Color(hex: NomiHex.white, opacity: 0.72)
  public static let tabGlassBottom = Color(hex: NomiHex.white, opacity: 0.42)
  public static let tabGlassBorder = Color(hex: NomiHex.white, opacity: 0.90)

  // MARK: - Glass blur

  public static let glassBlurRadius: CGFloat = 3
  public static let floatingGlassBlurRadius: CGFloat = 12
}

/// A drop shadow: colour, blur radius and offset. CSS blur B maps to `radius: B / 2`.
public struct NomiShadow {
  public let color: Color
  public let radius: CGFloat
  public let x: CGFloat
  public let y: CGFloat

  public init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
    self.color = color
    self.radius = radius
    self.x = x
    self.y = y
  }

  /// Cards and rows. The artboards use .10 and .14; one token at the midpoint.
  public static let card = NomiShadow(
    color: Color(hex: NomiHex.shadowCard, opacity: 0.12),
    radius: 11,
    x: 0,
    y: 8
  )
  /// The floating tab bar.
  public static let tabBar = NomiShadow(
    color: Color(hex: NomiHex.shadowTabBar, opacity: 0.18),
    radius: 16,
    x: 0,
    y: 12
  )
  /// The "+" button.
  public static let plus = NomiShadow(
    color: Color(hex: NomiHex.navyDeep, opacity: 0.35),
    radius: 9,
    x: 0,
    y: 8
  )
  /// Upward shadow under a hero sheet.
  public static let heroSheet = NomiShadow(
    color: Color(hex: NomiHex.shadowSheet, opacity: 0.08),
    radius: 12,
    x: 0,
    y: -6
  )
}

extension NomiColor {
  /// Legacy name for `NomiShadow`.
  public typealias ShadowToken = NomiShadow
}

extension Color {
  init(hex: UInt32, opacity: Double = 1) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: opacity
    )
  }
}

public extension View {
  /// Applies the card shadow (`NomiShadow.card`).
  func nomiShadow() -> some View {
    let token = NomiShadow.card
    return shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
  }
}
