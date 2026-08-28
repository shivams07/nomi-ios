import Charts
import Foundation
import NomiCore
import SwiftUI

/// Category breakdown for the selected period — same stacked-bar-plus-
/// ranked-list treatment as `Dashboard/CategoryBreakdownCard`, rebuilt here
/// rather than imported. It reuses U9's *aggregate* (`PeriodInsights.byCategory`,
/// from the shared `InsightsStore`), not U9's *view* — this unit's file
/// boundary excludes `Dashboard/**`, and the design doc's own delta table
/// calls Reports "a new surface" for this row (§2.1).
public struct ReportsCategoryBreakdownCard: View {
  public let slices: [CategorySlice]

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  private var folded: [CategorySlice] {
    ReportsCategoryFold.foldToSevenSlots(slices)
  }

  public var body: some View {
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
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRaised)
    .nomiCornerRadius(NomiRadius.card)
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

private func previewSlices() -> [CategorySlice] {
  let names = ["Food & Dining", "Shopping", "Transport", "Bills & Utilities"]
  return names.enumerated().map { index, name in
    CategorySlice(id: UUID(), name: name, paletteSlot: index, totalMinor: (4 - index) * 5000_00, share: 0.25)
  }
}

#Preview("Category breakdown — default, dark") {
  ReportsCategoryBreakdownCard(slices: previewSlices())
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Category breakdown — empty, dark") {
  ReportsCategoryBreakdownCard(slices: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Category breakdown — accessibility 3, dark") {
  ReportsCategoryBreakdownCard(slices: previewSlices())
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
