import SwiftUI

/// The Estate-Ease token set, transcribed from `apps/web/tailwind.config.ts` and
/// `docs/DESIGN.md`. Dark only — Nomi has no light appearance. FROZEN with the
/// rest of `Design/**` after U5; a missing token in a later unit is an
/// escalation, not something to add here quietly.
public enum NomiColor {
  // MARK: - Surface steps

  /// The canvas. Never `#000000` — DESIGN.md reserves true black for device chrome.
  public static let surfaceCanvas = Color(hex: 0x0c0c0c)
  /// Entry sheet composer, secondary buttons.
  public static let surface = Color(hex: 0x292929)
  /// Dashboard cards and other content sitting on the canvas.
  public static let surfaceRaised = Color(hex: 0x212121)
  /// Ledger rows once they become cards (`ui-ledger-surfaces`).
  public static let surfaceRow = Color(hex: 0x1C1C1C)
  /// Text inputs — amount field, note field.
  public static let surfaceInput = Color(hex: 0x1E1E1E)

  // MARK: - Glass

  public static let glassFill = Color.white.opacity(0.05)
  public static let glassHairline = Color.white.opacity(0.12)
  public static let glassHairlineStrong = Color.white.opacity(0.15)
  public static let glassBlurRadius: CGFloat = 3

  /// The floating tab bar's glass treatment — distinct from the card glass above.
  public static let floatingGlassFill = Color(hex: 0x151515).opacity(0.8)
  public static let floatingGlassHairline = Color.white.opacity(0.12)
  public static let floatingGlassBlurRadius: CGFloat = 12

  // MARK: - Accent

  /// Estate Ease Blue. One per screen, and only on the primary action.
  public static let accent = Color(hex: 0x0169FF)
  /// Scoped by rule (DB-24) to progress-track fills only — never chrome, never a CTA.
  public static let progressTrackFill = Color(hex: 0x2388FF)

  // MARK: - Text hierarchy (opacity, not colour)

  public static let textPrimary = Color.white
  public static let textSecondary = Color.white.opacity(0.91)
  public static let textTertiary = Color.white.opacity(0.62)
  public static let textQuaternary = Color(hex: 0x6D6D6D)

  // MARK: - Separators

  public static let separator = Color(red: 84.0 / 255, green: 84.0 / 255, blue: 88.0 / 255, opacity: 0.6)

  // MARK: - Direction

  /// Credits. 9.68:1 on `surfaceCanvas`, 8.43:1 on `surfaceRow` — both AA.
  public static let creditText = Color(hex: 0x30D158)
  /// Debits. 5.74:1 on `surfaceCanvas`, 5.00:1 on `surfaceRow` — both AA.
  public static let debitText = Color(hex: 0xFF453A)

  // MARK: - Over-budget

  /// Estate-Ease reserves red for destructive/error. Over-budget is neither, so
  /// it borrows the category-palette red slot at chip scale rather than a
  /// second, invented red.
  public static let overBudget = CategoryPalette.slots[6]

  // MARK: - The one sanctioned shadow

  /// Depth otherwise comes from fill lightness, hairline borders and blur — this
  /// is the only shadow anywhere in the system.
  public static let sanctionedShadow = ShadowToken(
    color: Color.black.opacity(0.1),
    radius: 40,
    x: 0,
    y: 2
  )

  public struct ShadowToken {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
  }
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
  /// Applies the one sanctioned shadow in the system.
  func nomiShadow() -> some View {
    let token = NomiColor.sanctionedShadow
    return shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
  }
}
