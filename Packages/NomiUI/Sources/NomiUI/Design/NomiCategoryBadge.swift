import SwiftUI

// clt-harness: include

/// A category's icon as the reference draws it: a circle filled with the
/// palette hue, white glyph. `paletteSlot` out of range (Other,
/// Uncategorized) fills with `CategoryPalette.other` — same fallback
/// `paletteSlot(_:)` already gives an out-of-range `Int`; `nil` maps to the
/// same fallback here. Sizes used: 28 chip row · 32 ledger/recent rows ·
/// 40 subscription rows and budget tiles · 56 transaction sheet header.
///
/// Rule amendment to v3 §conflict 2 ("never a surface fill"): a filled
/// circle of at most 56pt carrying a glyph is a *mark*, not a surface. The
/// palette is still never a card, a button, chrome or text. White glyph on
/// every slot is ≥ 3.07:1 (yellow is the floor; green 4.95); every slot
/// against `card` is ≥ 3.10:1 (`other` is the floor) — both clear
/// the 3:1 graphics threshold; neither is text.
///
/// `.neutral` is the F3 variant for Ledger and Home rows: an `iconTile` circle
/// with an `iconGlyph` glyph. The slot is ignored.
public struct NomiCategoryBadge: View {
  public enum Style: Sendable {
    case palette
    case neutral
  }

  public let symbolName: String
  public let slot: Int?
  public let size: CGFloat
  public let style: Style

  /// The symbol a category badge shows for an uncategorised row. A neutral
  /// badge with this symbol draws in the warning tones (amber, Activity board).
  static let uncategorisedSymbolName = "questionmark"

  public init(symbolName: String, paletteSlot: Int?, size: CGFloat, style: Style = .neutral) {
    self.symbolName = symbolName
    self.slot = paletteSlot
    self.size = size
    self.style = style
  }

  private var isUncategorised: Bool {
    symbolName == Self.uncategorisedSymbolName
  }

  private var resolvedFill: Color {
    switch style {
    case .palette:
      return paletteSlot(slot ?? -1)
    case .neutral:
      return isUncategorised ? NomiColor.warningTint : NomiColor.iconTile
    }
  }

  private var glyphColor: Color {
    switch style {
    case .palette:
      return NomiColor.onPrimary
    case .neutral:
      return isUncategorised ? NomiColor.warning : NomiColor.iconGlyph
    }
  }

  /// The side of the square the glyph is fitted into: 0.45 of the badge on
  /// both sides (D18). A width-only frame let a tall symbol such as
  /// "fork.knife" run past the circle's centre; a square cannot.
  static func glyphSide(for size: CGFloat) -> CGFloat {
    size * 0.45
  }

  var resolvedFillForTesting: Color { resolvedFill }
  var glyphColorForTesting: Color { glyphColor }

  public var body: some View {
    Circle()
      .fill(resolvedFill)
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: symbolName)
          .resizable()
          .scaledToFit()
          .frame(width: Self.glyphSide(for: size), height: Self.glyphSide(for: size))
          .foregroundStyle(glyphColor)
      }
  }
}

#Preview("Badges · palette and neutral · default") {
  VStack(alignment: .leading, spacing: 16) {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 28)
      NomiCategoryBadge(symbolName: "cart", paletteSlot: 4, size: 32)
      NomiCategoryBadge(symbolName: "play.tv", paletteSlot: 6, size: 40)
      NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 56)
    }
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      NomiCategoryBadge(symbolName: "bag", paletteSlot: nil, size: 32, style: .neutral)
      NomiCategoryBadge(symbolName: "car", paletteSlot: 1, size: 40, style: .neutral)
    }
  }
  .padding(NomiSpacing.sm)
  .background(NomiColor.card)
  .preferredColorScheme(.light)
}

#Preview("Badges · palette and neutral · AX3") {
  VStack(alignment: .leading, spacing: 16) {
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 28)
      NomiCategoryBadge(symbolName: "cart", paletteSlot: 4, size: 32)
      NomiCategoryBadge(symbolName: "play.tv", paletteSlot: 6, size: 40)
      NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 56)
    }
    HStack(alignment: .center, spacing: NomiSpacing.xs) {
      NomiCategoryBadge(symbolName: "bag", paletteSlot: nil, size: 32, style: .neutral)
      NomiCategoryBadge(symbolName: "car", paletteSlot: 1, size: 40, style: .neutral)
    }
  }
  .padding(NomiSpacing.sm)
  .background(NomiColor.card)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
