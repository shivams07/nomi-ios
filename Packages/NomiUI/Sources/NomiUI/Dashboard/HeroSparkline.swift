import Charts
import NomiCore
import SwiftUI

/// The hero card's cumulative-debit step line (v5 `nomi-ui-refresh` §Home) —
/// a pure `[Double]` builder so "last point equals the period's total" is
/// testable without rendering a `Chart`.
enum HeroSparkline {
  /// Sorted by day, cumulative `debitMinor`. `[]` when fewer than two
  /// buckets — the reference draws no line for a single day, and the view
  /// hides itself under that count rather than drawing a flat dot.
  static func points(byDay: [DayBucket]) -> [Double] {
    guard byDay.count >= 2 else { return [] }
    var running = 0
    return byDay.sorted { $0.id < $1.id }.map { bucket in
      running += bucket.debitMinor
      return Double(running)
    }
  }
}

/// 56pt tall, full width, flush — no axes, marks or grid. White @ 0.9 stroke
/// over a white @ 0.08 area, step-interpolated so the line rises to exactly
/// the hero figure. `Charts` is already a system-framework dependency this
/// module used elsewhere pre-v5, so this reuses it rather than hand-rolling
/// a `Path`.
struct HeroSparklineView: View {
  let byDay: [DayBucket]

  private var points: [Double] {
    HeroSparkline.points(byDay: byDay)
  }

  @ViewBuilder
  var body: some View {
    if points.isEmpty {
      EmptyView()
    } else {
      Chart(Array(points.enumerated()), id: \.offset) { index, value in
        AreaMark(x: .value("Day", index), y: .value("Cumulative spend", value))
          .interpolationMethod(.stepEnd)
          .foregroundStyle(Color.white.opacity(0.08))
        LineMark(x: .value("Day", index), y: .value("Cumulative spend", value))
          .interpolationMethod(.stepEnd)
          .foregroundStyle(Color.white.opacity(0.9))
          .lineStyle(StrokeStyle(lineWidth: 2))
      }
      .chartXAxis(.hidden)
      .chartYAxis(.hidden)
      .chartLegend(.hidden)
      .frame(height: 56)
    }
  }
}

#Preview("Hero sparkline — many buckets, dark") {
  HeroSparklineView(byDay: (0..<20).map { offset in
    DayBucket(
      id: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!,
      debitMinor: Int.random(in: 500...9000) * 100
    )
  })
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero sparkline — two buckets, dark") {
  HeroSparklineView(byDay: [
    DayBucket(id: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, debitMinor: 2000_00),
    DayBucket(id: Date(), debitMinor: 1500_00),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero sparkline — hidden under two buckets, dark") {
  HeroSparklineView(byDay: [DayBucket(id: Date(), debitMinor: 2000_00)])
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}
