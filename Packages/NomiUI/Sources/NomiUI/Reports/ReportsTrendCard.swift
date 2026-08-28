import Charts
import Foundation
import NomiCore
import SwiftUI

/// Income-vs-expense trend, 6 or 12 trailing months depending on basis.
/// Renders exactly what `[MonthBucket]` contains — never a fixed 6/12-slot
/// domain — so fewer than 6 (or 12) months of data renders fewer bars, per
/// the explicit AC ("the opposite of what a chart library does by default
/// with a fixed domain"). One shared y-scale for both series (no
/// `.chartYAxis` per-series override, no secondary axis) — grouped bars via
/// `foregroundStyle(by:)`, not two overlaid charts. Neither mark is
/// `NomiColor.accent` (same "no mark is blue" rule as `SpendPerDayChartCard`);
/// debit and credit are two distinct `CategoryPalette` slots rather than an
/// invented green/red pair, since the palette has no reserved income/expense
/// hues of its own.
public struct ReportsTrendCard: View {
  public let trend: [MonthBucket]

  public init(trend: [MonthBucket]) {
    self.trend = trend
  }

  private struct Point: Identifiable {
    let id: String
    let month: Date
    let series: String
    let amountMinor: Int
  }

  private var points: [Point] {
    trend.flatMap { bucket in
      [
        Point(id: "\(bucket.id)-debit", month: bucket.id, series: "Spent", amountMinor: bucket.debitMinor),
        Point(id: "\(bucket.id)-credit", month: bucket.id, series: "Received", amountMinor: bucket.creditMinor),
      ]
    }
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      Text("Income vs expense")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      if trend.isEmpty {
        Text("No trend data yet")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      } else {
        chart
      }
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRaised)
    .nomiCornerRadius(NomiRadius.card)
  }

  private var chart: some View {
    Chart(points) { point in
      BarMark(
        x: .value("Month", point.month, unit: .month),
        y: .value("Amount", Double(point.amountMinor) / 100)
      )
      .foregroundStyle(by: .value("Series", point.series))
      .position(by: .value("Series", point.series))
      .cornerRadius(4)
    }
    .chartForegroundStyleScale([
      "Spent": CategoryPalette.slots[1],
      "Received": CategoryPalette.slots[4],
    ])
    .chartXAxis {
      AxisMarks(values: .stride(by: .month)) { _ in
        AxisValueLabel(format: .dateTime.month(.abbreviated))
          .font(TabularFigures.font(name: NomiFont.interRegular, size: 11))
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
    .chartYAxis {
      AxisMarks { value in
        AxisValueLabel {
          if let major = value.as(Double.self) {
            Text(NomiFormatters.amountString(minor: Int(major * 100)))
              .font(TabularFigures.font(name: NomiFont.interRegular, size: 11))
          }
        }
        .foregroundStyle(NomiColor.textTertiary)
      }
    }
    .chartLegend(position: .bottom, spacing: NomiSpacing.xs)
    .frame(height: 180)
  }
}

private func previewTrend(monthCount: Int) -> [MonthBucket] {
  let calendar = Calendar(identifier: .gregorian)
  let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
  return (0..<monthCount).reversed().map { offset in
    let month = calendar.date(byAdding: .month, value: -offset, to: anchor)!
    return MonthBucket(id: month, debitMinor: (offset + 2) * 8000_00, creditMinor: (offset + 3) * 9000_00)
  }
}

#Preview("Trend — 12 months, dark") {
  ReportsTrendCard(trend: previewTrend(monthCount: 12))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Trend — 3 months of data, 3 bars, dark") {
  ReportsTrendCard(trend: previewTrend(monthCount: 3))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Trend — zero data, dark") {
  ReportsTrendCard(trend: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Trend — accessibility 3, dark") {
  ReportsTrendCard(trend: previewTrend(monthCount: 12))
    .padding()
    .background(NomiColor.surfaceCanvas)
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}
