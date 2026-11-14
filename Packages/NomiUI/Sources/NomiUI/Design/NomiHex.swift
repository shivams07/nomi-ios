// clt-harness: include

/// The single source of every colour value in the design layer: the Moss light
/// system (wave 1 F1 of nomi-ios redesign; values per the nomi-ios-moss-wave1
/// plan, I-9; canvas "Design system: Moss").
///
/// Integers only, so the contrast gates in `LightTokenTests` and
/// `DesignTokenTests` run on these values without rendering. `NomiColor`
/// builds every `Color` from here; nothing else in `Design/**` may restate a hex.
public enum NomiHex {
  // MARK: Ground and surfaces

  public static let ground: UInt32 = 0xF3F5F0
  public static let card: UInt32 = 0xFFFFFF
  /// Secondary fill. Carries the legacy `NomiColor.surface` name.
  public static let secondaryFill: UInt32 = 0xEEF3E8

  // MARK: Text

  public static let ink: UInt32 = 0x111411
  public static let inkDeep: UInt32 = 0x1F3320
  public static let inkSecondary: UInt32 = 0x566055
  public static let inkTab: UInt32 = 0x1F2A1F
  public static let dayHeader: UInt32 = 0x3C5A38
  public static let placeholder: UInt32 = 0x566055

  // MARK: Moss

  /// moss700: accent, links.
  public static let navy: UInt32 = 0x3C5A38
  /// moss900.
  public static let navyDeep: UInt32 = 0x1F3320
  /// moss500.
  public static let blueMid: UInt32 = 0x6B8E5E
  /// moss100.
  public static let track: UInt32 = 0xDDE8D3
  /// moss50.
  public static let iconTile: UInt32 = 0xEEF3E8
  public static let iconGlyph: UInt32 = 0x3C5A38

  /// Insights donut slices 3 and 4 (moss300 and moss100). Chart fills only,
  /// never text.
  public static let chartTintMid: UInt32 = 0xA9C39B
  public static let chartTintLight: UInt32 = 0xDDE8D3

  // MARK: Hero ramp (artboard points 0, 171, 313, 434, 504 at safe top 54)

  public static let heroRamp0: UInt32 = 0x1E3325
  public static let heroRamp1: UInt32 = 0x34543A
  public static let heroRamp2: UInt32 = 0x5F8558
  public static let heroRamp3: UInt32 = 0xA9C39B
  public static let heroRamp4: UInt32 = 0xD9E5CF

  // MARK: Controls

  public static let primary: UInt32 = 0x0C0F0C
  public static let onPrimary: UInt32 = 0xFFFFFF
  public static let white: UInt32 = 0xFFFFFF

  // MARK: Error

  /// The one error red (SIMP §5): error text, over-budget text and fill,
  /// destructive row text, the Backfill failure icon.
  public static let error: UInt32 = 0xB42318
  public static let errorTint: UInt32 = 0xFDECEA

  // MARK: Warning

  /// Warning text (the "close" tag and note text). Passes 4.5:1 on card and
  /// on `warningTint`.
  public static let warning: UInt32 = 0x8A5300
  /// Close-to-budget bar fill. Non-text, and below 3:1 on card: a bar that
  /// uses it must also carry the `warning` tag, so the state is never carried
  /// by the fill alone.
  public static let warningFill: UInt32 = 0xD99A1F
  public static let warningTint: UInt32 = 0xFBF0DA

  // MARK: Hero and tab glass

  public static let heroGlassSolid: UInt32 = 0x34543A

  /// The tint under the hero glass, at 52% (`NomiColor.heroGlassFill`). It is
  /// moss900 under Moss: dark glass keeps white hero text above 4.5:1 across
  /// the Backfill and Home backgrounds (plan I-9, Risks 2). The artboard's
  /// pill and gear carry a backdrop `saturate(170%)` that SwiftUI cannot
  /// reproduce, so the tint is fitted to the artboard's rendered pixels at
  /// the pill and the chip (fidelity D3).
  public static let heroGlassTint: UInt32 = 0x1F3320

  // MARK: Shadow colours (value and alpha live in `NomiShadow`)

  public static let shadowCard: UInt32 = 0x1F3320
  public static let shadowTabBar: UInt32 = 0x1F3320
  public static let shadowSheet: UInt32 = 0x1F3320
}
