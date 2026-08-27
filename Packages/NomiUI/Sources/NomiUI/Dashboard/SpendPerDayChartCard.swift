import Charts
import NomiCore
import SwiftUI

/// Card 2: a bar per day of debit spend, Swift Charts — a system framework,
/// so no `Package.swift` edit. Per the done-when: no mark is blue (the
/// category palette's slot 1 is used, never `NomiColor.accent`), bar caps are
/// 4pt, and axis ticks use the tabular-figures helper.
public struct SpendPerDayChartCard: View {
  public let byDay: [DayBucket]

  public init(byDay: [DayBucket]) {
    self.byDay = byDay
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Spend per day")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        if byDay.isEmpty {
          Text("No spend recorded this period")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.textTertiary)
        } else {
          chart
        }
      }
    }
  }

  private var chart: some View {
    Chart(byDay) { bucket in
      BarMark(
        x: .value("Day", bucket.id, unit: .day),
        y: .value("Spent", Double(bucket.debitMinor) / 100)
      )
      .foregroundStyle(CategoryPalette.slots[1])
      .cornerRadius(4)
    }
    .chartXAxis {
      AxisMarks { _ in
        AxisValueLabel()
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
    .frame(height: 160)
  }
}

#Preview("Spend per day — default, dark") {
  SpendPerDayChartCard(byDay: (0..<20).map { offset in
    DayBucket(
      id: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!,
      debitMinor: Int.random(in: 500...9000) * 100
    )
  })
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Spend per day — empty, dark") {
  SpendPerDayChartCard(byDay: [])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Spend per day — accessibility 3, dark") {
  SpendPerDayChartCard(byDay: (0..<20).map { offset in
    DayBucket(
      id: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!,
      debitMinor: Int.random(in: 500...9000) * 100
    )
  })
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
