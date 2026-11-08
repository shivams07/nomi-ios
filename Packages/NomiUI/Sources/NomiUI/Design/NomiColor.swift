// clt-harness: include
import SwiftUI

/// Nomi colour tokens: the approved light navy-ocean system (F1 of
/// nomi-ios-build-plan, I-1; SIMP §1 and §5). Light only. Every value comes
/// from `NomiHex`.
///
/// Existing names keep compiling so every screen follows the new values
/// without being rewritten. Legacy names that have a named replacement are
/// deprecated and carry the replacement's value; `textPrimary`, `textSecondary`,
/// `textTertiary`, `surfaceCanvas`, `surfaceRaised` and `surface` are not
/// deprecated in F1 (too many callers). X1 deletes the deprecated names once a
/// grep finds no callers.
public enum NomiColor {
  // MARK: - Ground and surfaces

  /// Screen and sheet ground. Legacy `surfaceCanvas`.
  public static let ground = Color(hex: NomiHex.ground)
  /// Cards, rows and inputs. Flat white, no glass.
  public static let card = Color(hex: NomiHex.card)
  /// Secondary fill. Legacy `surface`; no named replacement in I-1.
  public static let secondaryFill = Color(hex: NomiHex.secondaryFill)

  /// Legacy `surfaceCanvas`. Kept undeprecated; equals `ground`.
  public static let surfaceCanvas = Color(hex: NomiHex.ground)
  /// Legacy `surfaceRaised`. Kept undeprecated; equals `card`.
  public static let surfaceRaised = Color(hex: NomiHex.card)
  /// Legacy `surface`. Kept undeprecated; equals `secondaryFill`.
  public static let surface = Color(hex: NomiHex.secondaryFill)
  @available(*, deprecated, message: "Use NomiColor.card")
  public static let surfaceRow = Color(hex: NomiHex.card)
  @available(*, deprecated, message: "Use NomiColor.card")
  public static let surfaceInput = Color(hex: NomiHex.card)

  // MARK: - Text

  /// Primary text. Legacy `textPrimary`, not deprecated in F1.
  public static let ink = Color(hex: NomiHex.ink)
  /// Section labels, credit amounts, day ticks. Legacy `textSecondary`.
  public static let inkDeep = Color(hex: NomiHex.inkDeep)
  /// Captions, subtitles, values. Legacy `textTertiary`.
  public static let inkSecondary = Color(hex: NomiHex.inkSecondary)
  /// Unselected tab icon and label.
  public static let inkTab = Color(hex: NomiHex.inkTab)
  /// Ledger day header.
  public static let dayHeader = Color(hex: NomiHex.dayHeader)
  /// Text-field placeholder.
  public static let placeholder = Color(hex: NomiHex.placeholder)

  /// Legacy `textPrimary`. Kept undeprecated; equals `ink`.
  public static let textPrimary = Color(hex: NomiHex.ink)
  /// Legacy `textSecondary`. Kept undeprecated; equals `inkDeep`.
  public static let textSecondary = Color(hex: NomiHex.inkDeep)
  /// Legacy `textTertiary`. Kept undeprecated; equals `inkSecondary`.
  public static let textTertiary = Color(hex: NomiHex.inkSecondary)
  @available(*, deprecated, message: "Use NomiColor.inkTab")
  public static let textQuaternary = Color(hex: NomiHex.inkTab)

  // MARK: - Blue

  /// Back chevron, nav "+", links, switch on, selected chip and segment fill,
  /// chart marks, progress bar fill.
  public static let navy = Color(hex: NomiHex.navy)
  /// Top stop of the hero gradient.
  public static let navyDeep = Color(hex: NomiHex.navyDeep)
  /// Middle stop of the hero gradient.
  public static let blueMid = Color(hex: NomiHex.blueMid)
  /// Progress and ring track, hero tail.
  public static let track = Color(hex: NomiHex.track)
  /// Neutral row badge fill.
  public static let iconTile = Color(hex: NomiHex.iconTile)
  /// Neutral row badge glyph.
  public static let iconGlyph = Color(hex: NomiHex.iconGlyph)
  /// Insights donut slice 3 (artboard #8DB3EA). Chart fill only.
  public static let chartTintMid = Color(hex: NomiHex.chartTintMid)
  /// Insights donut slice 4 (artboard #BBD3EE). Chart fill only.
  public static let chartTintLight = Color(hex: NomiHex.chartTintLight)

  @available(*, deprecated, message: "Use NomiColor.navy")
  public static let accent = Color(hex: NomiHex.navy)
  @available(*, deprecated, message: "Use NomiColor.navy")
  public static let progressTrackFill = Color(hex: NomiHex.navy)

  // MARK: - Controls

  /// The one black primary control and the selected tab capsule.
  public static let primary = Color(hex: NomiHex.primary)
  /// Text and glyphs on `primary`, `navy` and `error` fills.
  public static let onPrimary = Color(hex: NomiHex.onPrimary)
  /// Switch track when off.
  public static let switchOff = Color(hex: NomiHex.switchOff)

  // MARK: - Error

  /// The one error red (SIMP §5): error text, over-budget text and bar fill,
  /// destructive row text, the Backfill failure icon.
  public static let error = Color(hex: NomiHex.error)
  /// Error card and icon tile fill.
  public static let errorTint = Color(hex: NomiHex.errorTint)

  /// Retired. Was the category-palette red slot borrowed for over-budget.
  /// Now `error`. Category colours never carry error meaning.
  @available(*, deprecated, message: "Use NomiColor.error")
  public static let overBudget = Color(hex: NomiHex.error)

  // MARK: - Direction

  /// Debits. Legacy `debitText`: ink with a minus sign, not red.
  @available(*, deprecated, message: "Use NomiColor.ink (debits carry the minus sign)")
  public static let debitText = Color(hex: NomiHex.ink)
  /// Credits. Legacy `creditText`: deep navy, semibold, with a plus sign.
  @available(*, deprecated, message: "Use NomiColor.inkDeep (credits carry the plus sign)")
  public static let creditText = Color(hex: NomiHex.inkDeep)

  // MARK: - Separators and scrim

  /// Card hairline and row divider: deep ink at 8%.
  public static let separator = Color(hex: NomiHex.inkDeep, opacity: 0.08)
  /// Reserved. Native sheets use system dimming; no iOS 17 API colours it.
  public static let scrim = Color(hex: NomiHex.navyDeep, opacity: 0.40)

  // MARK: - Decimals (SIMP §1 rule 4)

  /// Amount decimals on the white ground: ink at 65% (5.74:1 on card).
  public static let decimalOpacityGround: Double = 0.65
  /// Amount decimals on the hero: white at 60%.
  public static let decimalOpacityHero: Double = 0.60

  // MARK: - Hero (above y 264 only, SIMP §1 rule 2)

  public static let heroText = Color(hex: NomiHex.white)
  public static let heroTextSecondary = Color(hex: NomiHex.white, opacity: 0.80)
  /// Dark glass on the hero.
  public static let heroGlassFill = Color(hex: NomiHex.navyDeep, opacity: 0.30)
  public static let heroGlassBorder = Color(hex: NomiHex.white, opacity: 0.40)
  public static let heroGlassHighlight = Color(hex: NomiHex.white, opacity: 0.22)
  /// Reduce Transparency fallback for the hero glass.
  public static let heroGlassSolid = Color(hex: NomiHex.heroGlassSolid)

  // MARK: - Tab bar glass

  public static let tabGlassTop = Color(hex: NomiHex.white, opacity: 0.72)
  public static let tabGlassBottom = Color(hex: NomiHex.white, opacity: 0.42)
  public static let tabGlassBorder = Color(hex: NomiHex.white, opacity: 0.90)

  // MARK: - Legacy glass names

  @available(*, deprecated, message: "Use NomiColor.card")
  public static let glassFill = Color(hex: NomiHex.card)
  @available(*, deprecated, message: "Use NomiColor.separator")
  public static let glassHairline = Color(hex: NomiHex.inkDeep, opacity: 0.08)
  @available(*, deprecated, message: "Use NomiColor.separator")
  public static let glassHairlineStrong = Color(hex: NomiHex.inkDeep, opacity: 0.08)
  public static let glassBlurRadius: CGFloat = 3

  @available(*, deprecated, message: "Use NomiColor.tabGlassTop")
  public static let floatingGlassFill = Color(hex: NomiHex.white, opacity: 0.72)
  @available(*, deprecated, message: "Use NomiColor.tabGlassBorder")
  public static let floatingGlassHairline = Color(hex: NomiHex.white, opacity: 0.90)
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

  /// Legacy name for `NomiShadow.card`.
  @available(*, deprecated, message: "Use NomiShadow.card")
  public static let sanctionedShadow = NomiShadow.card
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
