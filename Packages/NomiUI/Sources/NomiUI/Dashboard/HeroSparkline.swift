import Charts
import NomiCore
import SwiftUI

/// The hero's cumulative spend line (HM1; the approved Main and HomeFirstRun
/// artboards). Pure builders, so "last point equals the period's total",
/// the date axis and the VoiceOver value are testable without rendering a
/// `Chart`.
enum HeroSparkline {
  /// Sorted by day, cumulative `debitMinor`. `[]` when fewer than two
  /// buckets: the hero draws a flat line for that, the same as zero spend.
  static func points(byDay: [DayBucket]) -> [Double] {
    guard byDay.count >= 2 else { return [] }
    var running = 0
    return byDay.sorted { $0.id < $1.id }.map { bucket in
      running += bucket.debitMinor
      return Double(running)
    }
  }

  /// One step of the line, placed on the calendar, so the x axis is the
  /// period's days and not the index of a spend day (`byDay` has no bucket
  /// for a day with no spend).
  struct Sample: Equatable {
    let date: Date
    let total: Double
  }

  /// The step line for `range`: starts at zero on the first day, takes each
  /// spend day's running total, and holds the final total to the end of the
  /// period. `[]` when `points` is empty, which draws the flat line.
  static func samples(byDay: [DayBucket], range: Range<Date>) -> [Sample] {
    let totals = points(byDay: byDay)
    guard let finalTotal = totals.last else { return [] }
    let days = byDay.sorted { $0.id < $1.id }.map(\.id)
    var samples = [Sample(date: range.lowerBound, total: 0)]
    for (day, total) in zip(days, totals) {
      samples.append(Sample(date: day, total: total))
    }
    samples.append(Sample(date: range.upperBound, total: finalTotal))
    return samples
  }

  /// The calendar range a period covers. Only calendar-month and
  /// financial-year periods reach the hero, and both are bounded.
  static func range(for period: InsightPeriod, calendar: Calendar = .current) -> Range<Date> {
    dateRange(for: period, calendar: calendar)
  }

  /// The two axis labels under the chart: the first and last day of the
  /// period. A month shows day numbers ("1", "30"), as the artboard does. A
  /// financial year shows "1 Apr" and "31 Mar", since a day number alone does
  /// not say which month it is.
  static func tickLabels(for period: InsightPeriod, calendar: Calendar = .current) -> (first: String, last: String) {
    let bounds = range(for: period, calendar: calendar)
    let lastDay = calendar.date(byAdding: .day, value: -1, to: bounds.upperBound) ?? bounds.upperBound
    switch period {
    case .month:
      return (
        "\(calendar.component(.day, from: bounds.lowerBound))",
        "\(calendar.component(.day, from: lastDay))"
      )
    case .financialYear, .trailingMonths, .allTime:
      return (
        NomiFormatters.dayMonth.string(from: bounds.lowerBound),
        NomiFormatters.dayMonth.string(from: lastDay)
      )
    }
  }

  /// The VoiceOver value. The running total only rises, so its highest point
  /// is the last spend day: "Highest on day N, ₹X".
  static func accessibilityValue(byDay: [DayBucket], calendar: Calendar = .current) -> String {
    guard let last = byDay.max(by: { $0.id < $1.id }) else {
      return "No spending this period"
    }
    let total = byDay.reduce(0) { $0 + $1.debitMinor }
    let day = calendar.component(.day, from: last.id)
    return "Highest on day \(day), \(NomiFormatters.amountString(minor: total))"
  }
}

/// The hero's chart: 64 pt tall, full width, flush. A white 2.5 pt step line
/// over a white 20% to 0% area, no axes, no tooltip. With no spend it is a
/// flat line at 40 pt from the top, as the first-run artboard draws it.
struct HeroSparklineView: View {
  let byDay: [DayBucket]
  let range: Range<Date>

  var body: some View {
    let samples = HeroSparkline.samples(byDay: byDay, range: range)
    Group {
      if samples.isEmpty {
        flatLine
      } else {
        chart(samples)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Spending this period")
    .accessibilityValue(HeroSparkline.accessibilityValue(byDay: byDay))
  }

  private var flatLine: some View {
    Capsule()
      .fill(NomiColor.heroText)
      .frame(height: 2.5)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(.top, 40 - 1.25)
  }

  private func chart(_ samples: [HeroSparkline.Sample]) -> some View {
    Chart(Array(samples.enumerated()), id: \.offset) { _, sample in
      AreaMark(x: .value("Day", sample.date), y: .value("Spent", sample.total))
        .interpolationMethod(.stepEnd)
        .foregroundStyle(
          LinearGradient(
            colors: [NomiColor.heroText.opacity(0.2), NomiColor.heroText.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
      LineMark(x: .value("Day", sample.date), y: .value("Spent", sample.total))
        .interpolationMethod(.stepEnd)
        .foregroundStyle(NomiColor.heroText)
        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
    .chartXScale(domain: range.lowerBound...range.upperBound)
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartLegend(.hidden)
  }
}
