import SwiftUI

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
/// against `surfaceRaised` is ≥ 3.10:1 (`other` is the floor) — both clear
/// the 3:1 graphics threshold; neither is text.
public struct NomiCategoryBadge: View {
  public let symbolName: String
  public let slot: Int?
  public let size: CGFloat

  public init(symbolName: String, paletteSlot: Int?, size: CGFloat) {
    self.symbolName = symbolName
    self.slot = paletteSlot
    self.size = size
  }

  private var resolvedFill: Color { paletteSlot(slot ?? -1) }

  var resolvedFillForTesting: Color { resolvedFill }

  public var body: some View {
    Circle()
      .fill(resolvedFill)
      .frame(width: size, height: size)
      .overlay(
        Image(systemName: symbolName)
          .font(.system(size: size * 0.45))
          .foregroundStyle(Color.white)
      )
  }
}

#Preview("28 · 32 · 40 · 56, a valid slot and a nil slot") {
  HStack(alignment: .center, spacing: NomiSpacing.sm) {
    NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 28)
    NomiCategoryBadge(symbolName: "cart", paletteSlot: 4, size: 32)
    NomiCategoryBadge(symbolName: "play.tv", paletteSlot: 6, size: 40)
    NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 56)
  }
  .padding()
  .background(NomiColor.surfaceRaised)
  .preferredColorScheme(.dark)
}
