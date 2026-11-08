import Charts
import Foundation
import NomiCore
import SwiftUI

/// The bar card on Insights: "Daily spend" for a calendar month (one bar per
/// day) or "Monthly spend" for a financial year (the trend's 12 months). Bars
/// are navy at 28%, with the highlighted bar (today, or the last bar) in full
/// navy. Only the first and last tick are printed, under the chart.
public struct ReportsTrendCard: View {
  public let title: String
  public let values: [Int]
  public let highlightIndex: Int?
  public let startLabel: String
  public let endLabel: String
  public let spokenValue: String

  public init(
    title: String,
    values: [Int],
    highlightIndex: Int?,
    startLabel: String,
    endLabel: String,
    spokenValue: String
  ) {
    self.title = title
    self.values = values
    self.highlightIndex = highlightIndex
    self.startLabel = startLabel
    self.endLabel = endLabel
    self.spokenValue = spokenValue
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text(title)
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
      chart
      HStack {
        Text(startLabel)
        Spacer(minLength: NomiSpacing.xs)
        Text(endLabel)
      }
      .nomiTextStyle(.micro)
      .foregroundStyle(NomiColor.inkSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 140, alignment: .topLeading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  private var chart: some View {
    Chart {
      ForEach(Array(values.enumerated()), id: \.offset) { index, amountMinor in
        BarMark(
          x: .value("Position", index + 1),
          y: .value("Spent", Double(amountMinor) / 100)
        )
        .foregroundStyle(index == highlightIndex ? NomiColor.navy : NomiColor.navy.opacity(0.28))
        .cornerRadius(3)
      }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
    .frame(height: 60)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(spokenValue)
  }
}

#Preview("Daily spend · November") {
  ReportsTrendCard(
    title: "Daily spend",
    values: [400_00, 1200_00, 800_00, 0, 2400_00, 900_00, 300_00, 1600_00, 700_00, 500_00],
    highlightIndex: 9,
    startLabel: "1",
    endLabel: "30",
    spokenValue: "Highest on day 5, ₹2,400.00"
  )
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Monthly spend · financial year") {
  ReportsTrendCard(
    title: "Monthly spend",
    values: [52000_00, 61000_00, 48000_00, 70000_00, 66000_00, 59000_00, 64000_00, 58000_00, 62000_00, 60000_00, 55000_00, 64824_24],
    highlightIndex: 11,
    startLabel: "Apr 25",
    endLabel: "Mar 26",
    spokenValue: "Highest in Jul 2025, ₹70,000.00"
  )
  .padding(20)
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Daily spend · AX3") {
  ReportsTrendCard(
    title: "Daily spend",
    values: [400_00, 1200_00, 800_00, 0, 2400_00],
    highlightIndex: 4,
    startLabel: "1",
    endLabel: "30",
    spokenValue: "Highest on day 5, ₹2,400.00"
  )
  .padding(20)
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
