import Foundation
import NomiCore

/// Folds an arbitrarily long category breakdown down to the seven-slot
/// palette's own limit — same rule as `Dashboard/CategoryBreakdownCard`'s
/// `CategoryFold`, duplicated per this unit's file boundary rather than
/// imported (see `ReportsPeriod`'s note). `paletteSlot: -1` is deliberate —
/// `paletteSlot(_:)` (Design/CategoryPalette.swift) already folds any
/// out-of-range slot to `CategoryPalette.other`, so reusing that resolver
/// here means Other never needs a second colour rule.
enum ReportsCategoryFold {
  static func foldToSevenSlots(_ slices: [CategorySlice]) -> [CategorySlice] {
    let sorted = slices.sorted { $0.totalMinor > $1.totalMinor }
    guard sorted.count > 7 else { return sorted }
    let kept = Array(sorted.prefix(7))
    let overflow = sorted.dropFirst(7)
    let otherTotal = overflow.reduce(0) { $0 + $1.totalMinor }
    let otherShare = overflow.reduce(0.0) { $0 + $1.share }
    let other = CategorySlice(id: otherOverflowID, name: "Other", paletteSlot: -1, totalMinor: otherTotal, share: otherShare)
    return kept + [other]
  }

  static let otherOverflowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000fe")!
}
