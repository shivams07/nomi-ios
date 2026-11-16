import Foundation
import NomiCore
import SwiftUI

/// The bars card on Insights (S6): "Last 6 months" on the calendar basis, "This
/// financial year" with twelve. Spent or Income, chosen by a segmented control.
/// Each bar is 10 pt round and `track`, and the period's own month is `primary`
/// (black). A bar's value is printed above it and its month below. Tapping a
/// bar opens that month.
struct ReportsTrendCard: View {
  let title: LocalizedStringKey
  let buckets: [MonthBucket]
  @Binding var kind: ReportsBarKind
  /// Any day in the selected month, which gets the black bar and the bold label.
  let selectedMonth: Date
  let calendar: Calendar
  /// The line under the bars, or `nil` for none.
  let caption: String?
  let onSelect: (MonthBucket) -> Void

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  init(
    title: LocalizedStringKey,
    buckets: [MonthBucket],
    kind: Binding<ReportsBarKind>,
    selectedMonth: Date,
    calendar: Calendar,
    caption: String?,
    onSelect: @escaping (MonthBucket) -> Void
  ) {
    self.title = title
    self.buckets = buckets
    self._kind = kind
    self.selectedMonth = selectedMonth
    self.calendar = calendar
    self.caption = caption
    self.onSelect = onSelect
  }

  private var values: [Int] {
    buckets.map { kind == .spent ? $0.debitMinor : $0.creditMinor }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: NomiSpacing.xs))
        : AnyLayout(HStackLayout(alignment: .center, spacing: NomiSpacing.xs))
      layout {
        Text(title, bundle: .module)
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
        ReportsKindControl(kind: $kind)
      }

      bars
        .frame(height: ReportsBars.columnHeight)

      if let caption {
        Text(verbatim: caption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: NomiSpacing.sm, leading: NomiSpacing.sm, bottom: NomiSpacing.sm, trailing: NomiSpacing.sm))
  }

  private var bars: some View {
    let values = values
    let peak = max(values.max() ?? 0, 1)
    return HStack(alignment: .bottom, spacing: buckets.count > 6 ? 4 : 10) {
      ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
        barColumn(bucket, value: values[index], peak: peak)
      }
    }
  }

  private func barColumn(_ bucket: MonthBucket, value: Int, peak: Int) -> some View {
    let isSelected = ReportsBars.isSameMonth(bucket.id, selectedMonth, calendar: calendar)
    let monthName = ReportsPeriod.monthName(for: bucket.id, calendar: calendar)
    return Button {
      onSelect(bucket)
    } label: {
      VStack(spacing: 6) {
        Text(verbatim: ReportsBarLabel.compact(minor: value))
          .nomiTextStyle(isSelected ? .label : .caption)
          .foregroundStyle(isSelected ? NomiColor.ink : NomiColor.inkSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(isSelected ? NomiColor.primary : NomiColor.track)
          .frame(height: ReportsBars.barHeight(value: value, peak: peak))
        Text(verbatim: ReportsBars.shortMonth(bucket.id, calendar: calendar))
          .nomiTextStyle(isSelected ? .label : .caption)
          .foregroundStyle(isSelected ? NomiColor.ink : NomiColor.inkSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(monthName), \(ReportsRupees.whole(minor: value))")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// The Spent / Income control's sizes. The drawn segment is `visualHeight`, and
/// its tap target is `tapHeight` (at least 44 pt, the HIG minimum).
enum ReportsKindSegments {
  static let visualHeight: CGFloat = 30
  static let tapHeight: CGFloat = 44
  /// The track's inset around the segments, as `NomiSegmented(.onGround)` draws it.
  static let trackInset: CGFloat = 4
}

/// The Spent / Income control, drawn as `NomiSegmented(.onGround, height: 30)`:
/// a track with 30 pt segments and a black selected capsule. Each segment's tap
/// target is 44 pt tall (`ReportsKindSegments.tapHeight`). The track keeps its
/// 38 pt height, so the target overflows it by 3 pt top and bottom and the
/// visual is unchanged. `NomiSegmented` itself is not changed for other callers.
private struct ReportsKindControl: View {
  @Binding var kind: ReportsBarKind

  var body: some View {
    HStack(spacing: ReportsKindSegments.trackInset) {
      segment(.spent, title: "Spent")
      segment(.income, title: "Income")
    }
    .padding(ReportsKindSegments.trackInset)
    .frame(height: ReportsKindSegments.visualHeight + 2 * ReportsKindSegments.trackInset)
    .background(Capsule().fill(NomiColor.secondaryFill))
  }

  private func segment(_ value: ReportsBarKind, title: LocalizedStringKey) -> some View {
    let isSelected = kind == value
    return Button {
      kind = value
    } label: {
      Text(title, bundle: .module)
        .font(.custom(NomiFont.interSemiBold, size: 15, relativeTo: .subheadline))
        .foregroundStyle(isSelected ? NomiColor.onPrimary : NomiColor.ink)
        .frame(maxWidth: .infinity)
        .frame(height: ReportsKindSegments.visualHeight)
        .background {
          if isSelected {
            Capsule().fill(NomiColor.primary)
          }
        }
        .frame(height: ReportsKindSegments.tapHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// Pure bar geometry and labels for `ReportsTrendCard` (S6).
enum ReportsBars {
  /// The tallest bar's height. The column above and below it adds the labels.
  static let maxBarHeight: CGFloat = 100
  /// A month with no spend still draws a bar this tall, so it is visible.
  static let stubHeight: CGFloat = 2
  /// The whole column: value label, bar, month label.
  static let columnHeight: CGFloat = 150

  /// The bar's height for `value` against the period's `peak`.
  static func barHeight(value: Int, peak: Int) -> CGFloat {
    guard peak > 0, value > 0 else { return stubHeight }
    return max(stubHeight, maxBarHeight * CGFloat(value) / CGFloat(peak))
  }

  static func isSameMonth(_ date: Date, _ other: Date, calendar: Calendar) -> Bool {
    calendar.isDate(date, equalTo: other, toGranularity: .month)
  }

  /// The three-letter month under a bar, "Sep".
  static func shortMonth(_ date: Date, calendar: Calendar) -> String {
    ReportsPeriod.shortMonthName(calendar.component(.month, from: date))
  }

  /// "November is 14 days in. Tap a month to open it.", for the month `now` is
  /// in. `nil` for any other period.
  static func caption(anchor: Date, now: Date, calendar: Calendar) -> String? {
    guard isSameMonth(anchor, now, calendar: calendar) else { return nil }
    let day = calendar.component(.day, from: now)
    let name = ReportsPeriod.monthName(for: now, calendar: calendar)
    return String(localized: "\(name) is \(day) days in. Tap a month to open it.", bundle: .module)
  }
}

/// A bar's value label: "999", "41k", "1.2L". Whole rupees below 1,000, rounded
/// thousands below a lakh, then lakhs to one decimal place. Rounding is half up.
enum ReportsBarLabel {
  static func compact(minor: Int) -> String {
    let rupees = (abs(minor) + 50) / 100
    if rupees < 1_000 {
      return String(rupees)
    }
    let thousands = (rupees + 500) / 1_000
    if thousands < 100 {
      return "\(thousands)k"
    }
    let tenths = (rupees + 5_000) / 10_000
    return "\(tenths / 10).\(tenths % 10)L"
  }
}
