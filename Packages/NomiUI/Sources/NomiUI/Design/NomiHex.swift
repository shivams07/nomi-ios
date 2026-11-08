// clt-harness: include

/// The single source of every colour value in the design layer: the approved
/// light navy-ocean system (F1 of nomi-ios-build-plan, I-1; SIMP §5).
///
/// Integers only, so the contrast gates in `LightTokenTests` and
/// `DesignTokenTests` run on these values without rendering. `NomiColor`
/// builds every `Color` from here; nothing else in `Design/**` may restate a hex.
public enum NomiHex {
  // MARK: Ground and surfaces

  public static let ground: UInt32 = 0xF3F6FB
  public static let card: UInt32 = 0xFFFFFF
  /// Secondary fill. Carries the legacy `NomiColor.surface` name.
  public static let secondaryFill: UInt32 = 0xEDF1F8

  // MARK: Text

  public static let ink: UInt32 = 0x0E1424
  public static let inkDeep: UInt32 = 0x0A2150
  public static let inkSecondary: UInt32 = 0x53607A
  public static let inkTab: UInt32 = 0x3A4660
  public static let dayHeader: UInt32 = 0x3D5486
  public static let placeholder: UInt32 = 0x5C6883

  // MARK: Blue

  public static let navy: UInt32 = 0x023571
  public static let navyDeep: UInt32 = 0x04174B
  public static let blueMid: UInt32 = 0x4F8AC4
  public static let track: UInt32 = 0xDCE8F5
  public static let iconTile: UInt32 = 0xE3EDFB
  public static let iconGlyph: UInt32 = 0x1B4290

  /// Insights donut slices 3 and 4, from the approved artboard (IN, decisions
  /// Amendment 2 R3). Chart fills only, never text.
  public static let chartTintMid: UInt32 = 0x8DB3EA
  public static let chartTintLight: UInt32 = 0xBBD3EE

  // MARK: Controls

  public static let primary: UInt32 = 0x06080F
  public static let onPrimary: UInt32 = 0xFFFFFF
  public static let switchOff: UInt32 = 0xC5CEDE
  public static let white: UInt32 = 0xFFFFFF

  // MARK: Error

  /// The one error red (SIMP §5): error text, over-budget text and fill,
  /// destructive row text, the Backfill failure icon.
  public static let error: UInt32 = 0xB42318
  public static let errorTint: UInt32 = 0xFDECEA

  // MARK: Hero and tab glass

  public static let heroGlassSolid: UInt32 = 0x0E3972

  /// End stop of the Backfill moment gradient (F3, DEC-09): navyDeep at 0,
  /// navy at 0.40, this at 1.0.
  public static let backfillEnd: UInt32 = 0x134883

  // MARK: Shadow colours (value and alpha live in `NomiShadow`)

  public static let shadowCard: UInt32 = 0x1E46AA
  public static let shadowTabBar: UInt32 = 0x0E2878
  public static let shadowSheet: UInt32 = 0x0E1E50
}
