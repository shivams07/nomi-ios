import Foundation
import NomiCore
import SwiftUI

/// "Spending by category" on Insights: the donut beside a legend of the
/// folded slices with their shares. At accessibility text sizes the legend
/// stacks under the donut. It reads the shared `PeriodInsights.byCategory`
/// through `ReportsCategoryFold`, so Other is folded the same way as before.
public struct ReportsCategoryBreakdownCard: View {
  public let slices: [CategorySlice]

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  public init(slices: [CategorySlice]) {
    self.slices = slices
  }

  private var folded: [CategorySlice] {
    ReportsCategoryFold.foldToSevenSlots(slices)
  }

  private var total: Int {
    folded.reduce(0) { $0 + $1.totalMinor }
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("Spending by category")
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
      if folded.isEmpty || total <= 0 {
        Text("No categorized spend this period")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      } else {
        breakdown
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 140, alignment: .topLeading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  @ViewBuilder
  private var breakdown: some View {
    let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: NomiSpacing.sm))
      : AnyLayout(HStackLayout(alignment: .center, spacing: NomiSpacing.sm))
    layout {
      ReportsDonut(slices: folded)
      legend
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: 6) {
      let percents = ReportsDonut.percentages(folded)
      ForEach(Array(folded.enumerated()), id: \.element.id) { index, slice in
        HStack(spacing: 10) {
          Circle()
            .fill(ReportsDonut.color(at: index))
            .frame(width: 10, height: 10)
          Text(slice.name)
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.ink)
            .lineLimit(1)
          Spacer(minLength: NomiSpacing.xs)
          Text("\(percents[index])%")
            .nomiTextStyle(.label)
            .foregroundStyle(NomiColor.ink)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

#Preview("Category breakdown · default") {
  ReportsCategoryBreakdownCard(slices: [
    CategorySlice(id: UUID(), name: "Food & Dining", paletteSlot: 0, totalMinor: 25_900_00, share: 0.4),
    CategorySlice(id: UUID(), name: "Shopping", paletteSlot: 1, totalMinor: 15_500_00, share: 0.24),
    CategorySlice(id: UUID(), name: "Transport", paletteSlot: 2, totalMinor: 10_300_00, share: 0.16),
    CategorySlice(id: UUID(), name: "Other", paletteSlot: 3, totalMinor: 13_100_00, share: 0.2),
  ])
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Category breakdown · empty") {
  ReportsCategoryBreakdownCard(slices: [])
    .padding(20)
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Category breakdown · AX3") {
  ReportsCategoryBreakdownCard(slices: [
    CategorySlice(id: UUID(), name: "Food & Dining", paletteSlot: 0, totalMinor: 25_900_00, share: 0.4),
    CategorySlice(id: UUID(), name: "Shopping", paletteSlot: 1, totalMinor: 15_500_00, share: 0.24),
  ])
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
