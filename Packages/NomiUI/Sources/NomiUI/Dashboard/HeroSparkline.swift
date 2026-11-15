import Foundation
import NomiCore
import SwiftUI

/// The hero's chart data and labels (S1a; the approved Main artboard). Pure
/// builders, so the dense series, the axis labels and the VoiceOver value are
/// testable without rendering.
enum HeroSparkline {
  /// The period's calendar range, from the one range source.
  static func range(for period: InsightPeriod, calendar: Calendar = .current) -> Range<Date> {
    dateRange(for: period, calendar: calendar)
  }

  /// "1 Nov" and "30 Nov", as the artboard reads. A financial year reads the
  /// same way ("1 Apr", "31 Mar").
  static func tickLabels(for period: InsightPeriod, calendar: Calendar = .current) -> (first: String, last: String) {
    let bounds = range(for: period, calendar: calendar)
    let lastDay = calendar.date(byAdding: .day, value: -1, to: bounds.upperBound) ?? bounds.upperBound
    return (dayMonthText(bounds.lowerBound, calendar: calendar), dayMonthText(lastDay, calendar: calendar))
  }

  /// "14 Nov", read in the calendar's own zone. A formatter at the process
  /// default names the day before in a zone west of the calendar's.
  static func dayMonthText(_ date: Date, calendar: Calendar) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "d MMM"
    return formatter.string(from: date)
  }

  /// The VoiceOver value: the last day the kind counted, and the total. An
  /// income-only month reads "No spending" on the spent line, and an
  /// income day is never counted as spending.
  static func accessibilityValue(
    byDay: [DayBucket],
    kind: NomiComparisonCopy.Kind = .spent,
    calendar: Calendar = .current
  ) -> String {
    let counted = byDay.filter { amount(of: $0, kind: kind) != 0 }
    guard let last = counted.max(by: { $0.id < $1.id }) else {
      return kind == .spent ? "No spending this period" : "No income this period"
    }
    let total = counted.reduce(0) { $0 + amount(of: $1, kind: kind) }
    let day = calendar.component(.day, from: last.id)
    return "Highest on day \(day), \(NomiFormatters.amountString(minor: total))"
  }

  /// The minor units a day counts for this line: debit for spent, credit for income.
  static func amount(of bucket: DayBucket, kind: NomiComparisonCopy.Kind) -> Int {
    kind == .spent ? bucket.debitMinor : bucket.creditMinor
  }
}

/// The dense daily series behind the hero's lines (S1a, I-10). `byDay` is
/// sparse, so the day-by-day values are filled here.
enum HomeSparklineSeries {
  /// The number of calendar days in `range`.
  static func dayCount(in range: Range<Date>, calendar: Calendar = .current) -> Int {
    max(0, dayIndex(of: range.upperBound, from: range.lowerBound, calendar: calendar))
  }

  /// The running total of the kind's amount, one value per day of
  /// `periodRange` from its first day through `today`. A period that ends
  /// before today runs to its last day. Empty when today is before the period.
  static func cumulative(
    byDay: [DayBucket],
    kind: NomiComparisonCopy.Kind,
    periodRange: Range<Date>,
    today: Date,
    calendar: Calendar
  ) -> [Double] {
    let count = dayCount(in: periodRange, calendar: calendar)
    let todayIndex = dayIndex(of: today, from: periodRange.lowerBound, calendar: calendar)
    guard count > 0, todayIndex >= 0 else { return [] }

    var perDay = Array(repeating: 0, count: count)
    for bucket in byDay {
      let index = dayIndex(of: bucket.id, from: periodRange.lowerBound, calendar: calendar)
      guard index >= 0, index < count else { continue }
      perDay[index] += HeroSparkline.amount(of: bucket, kind: kind)
    }

    var running = 0
    return (0...min(todayIndex, count - 1)).map { index in
      running += perDay[index]
      return Double(running)
    }
  }

  /// The prior window's series, index-aligned to the current period's days.
  /// A longer prior is cut to `count`. A shorter one (February before a
  /// 31-day month) holds its final total to the end.
  static func aligned(_ prior: [Double], count: Int) -> [Double] {
    guard count > 0, let held = prior.last else { return [] }
    if prior.count >= count { return Array(prior.prefix(count)) }
    return prior + Array(repeating: held, count: count - prior.count)
  }

  /// Whole days from `start` to `date`, both read at the start of their day.
  static func dayIndex(of date: Date, from start: Date, calendar: Calendar) -> Int {
    calendar.dateComponents(
      [.day],
      from: calendar.startOfDay(for: start),
      to: calendar.startOfDay(for: date)
    ).day ?? 0
  }
}

/// Where a chart value sits (S1a). The line runs from `topInset` (the largest
/// value) down to the baseline. The headroom above it is the tooltip's space.
enum HomeSparklinePlot {
  static let topInset: CGFloat = 56
  static let bottomInset: CGFloat = 2

  /// `index` of `span` days, on a width of `size.width`, with `value` scaled
  /// against `maxValue`.
  static func point(index: Int, value: Double, span: Int, maxValue: Double, size: CGSize) -> CGPoint {
    let x = span > 1 ? size.width * CGFloat(index) / CGFloat(span - 1) : 0
    let bottom = size.height - bottomInset
    let fraction = maxValue > 0 ? CGFloat(value / maxValue) : 0
    let y = bottom - (bottom - topInset) * fraction
    return CGPoint(x: x, y: y)
  }

  /// The largest value across the lines, never below 1 so the scale holds for an empty month.
  static func maxValue(_ series: [Double]...) -> Double {
    max(1, series.flatMap { $0 }.max() ?? 1)
  }
}

/// The hero's chart (S1a): 150 pt tall, full width. A white 2 pt line to today,
/// a dashed white 45% line from today to the period's end, a faint white 40%
/// 1.5 pt line over the whole period for the prior one, a white dot at today
/// with a black tooltip above it, and the two day labels with the faint line's
/// name between them.
struct HeroSparklineView: View {
  static let height: CGFloat = 150

  /// Dense through today, one value per day.
  let current: [Double]
  /// The prior window aligned to `span`, or `nil` when there is no prior period.
  let prior: [Double]?
  /// The number of days in the period.
  let span: Int
  let tipMinor: Int
  let tipDate: String
  let startLabel: String
  let endLabel: String
  let priorLabel: String?
  let accessibilityLabel: String
  let accessibilityValue: String

  var body: some View {
    VStack(spacing: 8) {
      chart
        .frame(height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
      axisLabels
    }
  }

  private var chart: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let maxValue = HomeSparklinePlot.maxValue(current, prior ?? [])
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          if let prior, prior.count > 1 {
            context.stroke(
              linePath(prior, size: size, maxValue: maxValue),
              with: .color(NomiColor.heroText.opacity(0.4)),
              style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
          }
          if let last = current.last, let lastIndex = current.indices.last {
            context.stroke(
              linePath(current, size: size, maxValue: maxValue),
              with: .color(NomiColor.heroText),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            let todayPoint = HomeSparklinePlot.point(
              index: lastIndex, value: last, span: span, maxValue: maxValue, size: size
            )
            let endPoint = HomeSparklinePlot.point(
              index: span - 1, value: last, span: span, maxValue: maxValue, size: size
            )
            var dashed = Path()
            dashed.move(to: todayPoint)
            dashed.addLine(to: endPoint)
            context.stroke(
              dashed,
              with: .color(NomiColor.heroText.opacity(0.45)),
              style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 5])
            )
            context.fill(
              Path(ellipseIn: CGRect(x: todayPoint.x - 4, y: todayPoint.y - 4, width: 8, height: 8)),
              with: .color(NomiColor.heroText)
            )
          }
        }
        if let last = current.last, let lastIndex = current.indices.last {
          let todayPoint = HomeSparklinePlot.point(
            index: lastIndex, value: last, span: span, maxValue: maxValue, size: size
          )
          tooltip(at: todayPoint, size: size)
        }
      }
      .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
  }

  /// The black tooltip, centred on the dot and kept inside the chart's width,
  /// with its bottom 8 pt above the dot.
  private func tooltip(at point: CGPoint, size: CGSize) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(NomiFormatters.amountString(minor: tipMinor))
        .font(.custom(NomiFont.interSemiBold, size: 15, relativeTo: .headline))
      Text(verbatim: tipDate)
        .font(.custom(NomiFont.interRegular, size: 12, relativeTo: .caption))
    }
    .foregroundStyle(NomiColor.heroText)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(NomiColor.primary)
    )
    .fixedSize()
    .alignmentGuide(.leading) { dimensions in
      -min(max(point.x - dimensions.width / 2, 0), max(0, size.width - dimensions.width))
    }
    .alignmentGuide(.top) { dimensions in
      -max(0, point.y - dimensions.height - 8)
    }
  }

  private func linePath(_ values: [Double], size: CGSize, maxValue: Double) -> Path {
    var path = Path()
    for (index, value) in values.enumerated() {
      let point = HomeSparklinePlot.point(index: index, value: value, span: span, maxValue: maxValue, size: size)
      if index == 0 {
        path.move(to: point)
      } else {
        path.addLine(to: point)
      }
    }
    return path
  }

  private var axisLabels: some View {
    HStack(spacing: 8) {
      Text(startLabel)
      Spacer(minLength: 8)
      if let priorLabel {
        Text("Faint line: \(priorLabel)", bundle: .module)
        Spacer(minLength: 8)
      }
      Text(endLabel)
    }
    .font(.custom(NomiFont.interSemiBold, size: 12, relativeTo: .caption))
    .foregroundStyle(NomiColor.navyDeep)
    .lineLimit(1)
    .minimumScaleFactor(0.75)
    .accessibilityHidden(true)
  }
}
