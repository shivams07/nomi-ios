import NomiCore
import SwiftUI

/// Folds an arbitrarily long category breakdown down to the seven-slot
/// palette's own limit: the 7 largest slices keep their real colour, and
/// everything from rank 8 on rolls into a single "Other" slice. `paletteSlot:
/// -1` is deliberate — `paletteSlot(_:)` (Design/CategoryPalette.swift)
/// already folds any out-of-range slot to `CategoryPalette.other`, so reusing
/// that resolver here means Other never needs a second colour rule.
enum CategoryFold {
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

  static let otherOverflowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000ff")!
}

/// Card 5 (v5 `nomi-ui-refresh` §Home): "Top spending" — a horizontal scroll
/// of chips, one per folded slice. Replaces v4's stacked bar + ranked list
/// entirely (this file used to hold that card, under its old name, before
/// the `git mv` to this one); `CategoryFold` survives unchanged, and
/// `CategoryBreakdownFoldTests` next door still exercises it.
public struct CategoryChipRow: View {
  public let slices: [CategorySlice]

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  private var folded: [CategorySlice] {
    CategoryFold.foldToSevenSlots(slices)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      Text("Top spending")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      if folded.isEmpty {
        Text("No categorized spend this period")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: NomiSpacing.xs) {
            ForEach(folded) { slice in
              chip(for: slice)
            }
          }
        }
      }
    }
  }

  private func chip(for slice: CategorySlice) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      NomiCategoryBadge(symbolName: slice.symbolName, paletteSlot: slice.paletteSlot, size: 28)
      VStack(alignment: .leading, spacing: 0) {
        Text(slice.name)
          .nomiTextStyle(.body)
          .foregroundStyle(Color.white)
          .lineLimit(1)
        Text(NomiFormatters.amountString(minor: slice.totalMinor))
          .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
          .foregroundStyle(NomiColor.textSecondary)
      }
    }
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, NomiSpacing.xs)
    .background(NomiColor.surface)
    .clipShape(Capsule(style: .continuous))
  }
}

#Preview("Top spending — default, dark") {
  let names = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities"]
  let slices = names.enumerated().map { index, name in
    CategorySlice(id: UUID(), name: name, paletteSlot: index, totalMinor: (4 - index) * 5000_00, share: 0.25)
  }
  CategoryChipRow(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Top spending — eight categories fold to Other, dark") {
  let slices = (0..<8).map { index in
    CategorySlice(id: UUID(), name: "Category \(index + 1)", paletteSlot: index % 7, totalMinor: (8 - index) * 3000_00, share: 0.1)
  }
  CategoryChipRow(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Top spending — empty, dark") {
  CategoryChipRow(slices: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Top spending — accessibility 3, dark") {
  let names = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities"]
  let slices = names.enumerated().map { index, name in
    CategorySlice(id: UUID(), name: name, paletteSlot: index, totalMinor: (4 - index) * 5000_00, share: 0.25)
  }
  CategoryChipRow(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
