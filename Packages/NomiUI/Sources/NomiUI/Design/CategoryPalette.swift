import SwiftUI

/// The v3 category palette — seven slots, fixed order, never cycled. Re-validated
/// against Nomi's real dark surfaces (`#212121`, `#1c1c1c`, `#0c0c0c`, `#292929`):
/// worst adjacent CVD ΔE 8.4 (protan), worst adjacent normal-vision ΔE 19.3, every
/// slot ≥3:1. Blue is deliberately absent — it belongs to the primary action only.
///
/// This palette answers a different question than `NomiColor`: chrome vs. data.
/// It never appears as a surface fill, a button, a text colour or chrome — only
/// inside chart marks and category chips.
public enum CategoryPalette {
  /// Fixed order: orange, aqua, yellow, magenta, green, violet, red.
  public static let slots: [Color] = [
    Color(hex: 0xd9_59_26), // 1 orange
    Color(hex: 0x19_9e_70), // 2 aqua
    Color(hex: 0xc9_85_00), // 3 yellow
    Color(hex: 0xd5_51_81), // 4 magenta
    Color(hex: 0x00_83_00), // 5 green
    Color(hex: 0x90_85_e9), // 6 violet
    Color(hex: 0xe6_67_67), // 7 red
  ]

  /// Neutral grey for anything past slot 6 — an 8th category folds to Other.
  /// A generated hue is never produced.
  public static let other = Color(hex: 0x6D_6D_6D)
}

/// The slot -> hue resolver. `Category.paletteSlot` (0-indexed, 0...6) is the
/// only source of truth for a category's colour; `Design/**` owns the seven
/// hues and this mapping. An out-of-range slot (the 8th-and-beyond category)
/// resolves to `CategoryPalette.other`, never a generated hue.
public func paletteSlot(_ slot: Int) -> Color {
  guard CategoryPalette.slots.indices.contains(slot) else {
    return CategoryPalette.other
  }
  return CategoryPalette.slots[slot]
}
