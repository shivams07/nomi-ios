import Charts
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

/// Card 3: category spend as a horizontal stacked bar PLUS the ranked list —
/// two views of the same folded data, per the U9 notes ("PLUS the ranked
/// list").
public struct CategoryBreakdownCard: View {
  public let slices: [CategorySlice]

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  private var folded: [CategorySlice] {
    CategoryFold.foldToSevenSlots(slices)
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Category breakdown")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if folded.isEmpty {
          Text("No categorized spend this period")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          stackedBar
          rankedList
        }
      }
    }
  }

  private var stackedBar: some View {
    Chart(folded) { slice in
      BarMark(
        x: .value("Amount", slice.totalMinor),
        y: .value("Row", "Total")
      )
      .foregroundStyle(paletteSlot(slice.paletteSlot))
      .cornerRadius(4)
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
    .frame(height: 24)
  }

  private var rankedList: some View {
    VStack(spacing: NomiSpacing.xs) {
      ForEach(folded) { slice in
        HStack(spacing: NomiSpacing.xs) {
          Circle()
            .fill(paletteSlot(slice.paletteSlot))
            .frame(width: 8, height: 8)
          Text(slice.name)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textPrimary)
            .lineLimit(1)
          Spacer(minLength: NomiSpacing.xs)
          Text(NomiFormatters.amountString(minor: slice.totalMinor))
            .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
            .foregroundStyle(NomiColor.textSecondary)
        }
      }
    }
  }
}

#Preview("Category breakdown — default, dark") {
  let names = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities"]
  let slices = names.enumerated().map { index, name in
    CategorySlice(id: UUID(), name: name, paletteSlot: index, totalMinor: (4 - index) * 5000_00, share: 0.25)
  }
  CategoryBreakdownCard(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Category breakdown — eight categories fold to Other, dark") {
  let slices = (0..<8).map { index in
    CategorySlice(id: UUID(), name: "Category \(index + 1)", paletteSlot: index % 7, totalMinor: (8 - index) * 3000_00, share: 0.1)
  }
  CategoryBreakdownCard(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Category breakdown — empty, dark") {
  CategoryBreakdownCard(slices: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Category breakdown — accessibility 3, dark") {
  let names = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities"]
  let slices = names.enumerated().map { index, name in
    CategorySlice(id: UUID(), name: name, paletteSlot: index, totalMinor: (4 - index) * 5000_00, share: 0.25)
  }
  CategoryBreakdownCard(slices: slices)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
