import NomiCore
import SwiftUI

/// The hero's comparison chip (S1a). The words are `NomiComparisonCopy`'s, so
/// this type decides only which figure is compared, which way the arrow
/// points, and when there is nothing to state.
enum HeroComparison {
  enum Direction: Equatable {
    case up
    case down
  }

  struct Chip: Equatable {
    let text: String
    /// `nil` when the copy has no direction: an equal figure, or an empty earlier period.
    let direction: Direction?
  }

  /// The figure the kind counts for this period.
  static func amount(kind: NomiComparisonCopy.Kind, insights: PeriodInsights) -> Int {
    kind == .spent ? insights.debitMinor : insights.creditMinor
  }

  /// The same figure for the earlier period, `nil` when there is none.
  static func priorAmount(kind: NomiComparisonCopy.Kind, insights: PeriodInsights) -> Int? {
    kind == .spent ? insights.priorDebitMinor : insights.priorCreditMinor
  }

  /// The chip for this kind, or `nil` when there is nothing to say. Nothing is
  /// said when there is no earlier period, and when the figure and its earlier
  /// period are both zero (FR1: the first-run Home draws no chip). An empty
  /// earlier period reads "Nothing spent in <label> to compare", never a figure
  /// of zero to compare against.
  static func chip(kind: NomiComparisonCopy.Kind, insights: PeriodInsights, priorLabel: String) -> Chip? {
    let current = amount(kind: kind, insights: insights)
    let prior = priorAmount(kind: kind, insights: insights)
    if current == 0, (prior ?? 0) == 0 {
      return nil
    }
    guard let text = NomiComparisonCopy.line(
      kind: kind,
      currentMinor: current,
      priorMinor: prior,
      priorLabel: priorLabel
    ) else {
      return nil
    }
    // The copy's arrow only means something against a real earlier figure.
    guard let prior, prior != 0, current != prior else {
      return Chip(text: text, direction: nil)
    }
    return Chip(text: text, direction: current < prior ? .down : .up)
  }
}

/// The Home hero (S1a; the approved Main artboard): the Spent or Income control,
/// the label with its comparison chip, the figure, and the chart. The figure
/// is `Figures.loaded` only when the period's insights were read. Loading and
/// failure keep the same layout, so the sheet below does not move.
struct HeroTotalCard: View {
  enum Figures {
    case loading
    case unavailable
    case loaded(PeriodInsights)
  }

  let figures: Figures
  let period: InsightPeriod
  @Binding var kind: NomiComparisonCopy.Kind

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var displayedMinor = 0

  /// S1b step 6. At accessibility sizes the comparison chip goes under its label,
  /// so the chip's words wrap rather than truncate (PR 213: "↑ ₹4,804 more…"). At
  /// the standard sizes the two share a row, as on the artboard.
  static func labelRowStacks(_ size: DynamicTypeSize) -> Bool {
    size.isAccessibilitySize
  }

  init(figures: Figures, period: InsightPeriod, kind: Binding<NomiComparisonCopy.Kind>) {
    self.figures = figures
    self.period = period
    self._kind = kind
    if case .loaded(let insights) = figures {
      _displayedMinor = State(initialValue: HeroComparison.amount(kind: kind.wrappedValue, insights: insights))
    }
  }

  /// "Spent this month", "Received this year" and so on. The label names the
  /// kind and the basis, and never the figure.
  static func label(kind: NomiComparisonCopy.Kind, period: InsightPeriod) -> String {
    switch (kind, period) {
    case (.spent, .month):
      return String(localized: "Spent this month", bundle: .module)
    case (.income, .month):
      return String(localized: "Received this month", bundle: .module)
    case (.spent, .financialYear):
      return String(localized: "Spent this year", bundle: .module)
    case (.income, .financialYear):
      return String(localized: "Received this year", bundle: .module)
    case (.spent, _):
      return String(localized: "Spent this period", bundle: .module)
    case (.income, _):
      return String(localized: "Received this period", bundle: .module)
    }
  }

  /// The Spent or Income control. At accessibility sizes the arrow glyphs go:
  /// they take the width the words need, and at AX3 "Income" broke mid-word
  /// ("Inco / me"). The words stay; only the decoration drops.
  static func options(for size: DynamicTypeSize) -> [(value: NomiComparisonCopy.Kind, title: String, systemImage: String?)] {
    let showsIcons = segmentShowsIcons(size)
    return [
      (value: .spent, title: "Spent", systemImage: showsIcons ? "arrow.down" : nil),
      (value: .income, title: "Income", systemImage: showsIcons ? "arrow.up" : nil),
    ]
  }

  /// Whether the segments draw their arrow glyphs. Standard sizes keep them, as on
  /// the artboard; accessibility sizes drop them so each word has the whole segment.
  static func segmentShowsIcons(_ size: DynamicTypeSize) -> Bool {
    !size.isAccessibilitySize
  }

  /// Whether the nav row stacks: at accessibility sizes the period pill takes a row
  /// of its own, so its title wraps onto lines instead of truncating ("Novemb…"),
  /// and the Search and Settings circles move to a trailing row beneath it.
  static func navRowStacks(_ size: DynamicTypeSize) -> Bool {
    size.isAccessibilitySize
  }

  private var targetMinor: Int {
    guard case .loaded(let insights) = figures else { return 0 }
    return HeroComparison.amount(kind: kind, insights: insights)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      NomiSegmented(Self.options(for: dynamicTypeSize), selection: $kind, style: .onHero)
        .padding(.top, 6)
      switch figures {
      case .loaded(let insights):
        loaded(insights)
      case .loading, .unavailable:
        placeholder
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { animateIn() }
    .onChange(of: targetMinor) { _, _ in animateIn() }
  }

  private func loaded(_ insights: PeriodInsights) -> some View {
    let chip = HeroComparison.chip(kind: kind, insights: insights, priorLabel: priorLabel(for: insights))
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        labelRow(chip: chip)
        NomiAmountText(
          minor: displayedMinor,
          context: .hero,
          style: .heroAmount,
          accessibilityLabel: "\(Self.label(kind: kind, period: period)), \(NomiFormatters.amountString(minor: targetMinor))"
        )
        .contentTransition(.numericText(value: Double(displayedMinor)))
        .padding(.top, 8)
      }
      .padding(.top, 22)
      NomiHeroChartSlot {
        chart(insights)
          .padding(.top, 14)
      }
    }
  }

  /// The loading and failed hero: the same label row, a "₹—" figure, and the
  /// same space for the chart, so the sheet starts where it does when loaded.
  private var placeholder: some View {
    let accessibility: String
    switch figures {
    case .loading:
      accessibility = String(localized: "Loading spending", bundle: .module)
    case .unavailable, .loaded:
      accessibility = String(localized: "Spending unavailable", bundle: .module)
    }
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        labelRow(chip: nil)
        Text("₹—")
          .nomiTextStyle(.heroAmount)
          .foregroundStyle(NomiColor.heroText)
          .lineLimit(1)
          .accessibilityLabel(accessibility)
          .padding(.top, 8)
      }
      .padding(.top, 22)
      NomiHeroChartSlot {
        Color.clear
          .frame(height: 14 + HeroSparklineView.height + 8 + 16)
      }
    }
  }

  private func labelRow(chip: HeroComparison.Chip?) -> some View {
    let wraps = Self.labelRowStacks(dynamicTypeSize)
    let label = Text(Self.label(kind: kind, period: period))
      .nomiTextStyle(.chip)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
    return Group {
      if wraps {
        VStack(alignment: .leading, spacing: 8) {
          label
          if let chip {
            HeroComparisonChip(chip: chip, wraps: true)
          }
        }
      } else {
        HStack(alignment: .center, spacing: 8) {
          label
          if let chip {
            HeroComparisonChip(chip: chip, wraps: false)
          }
        }
      }
    }
    .foregroundStyle(NomiColor.heroText)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The chart and its inputs, all from the figures already loaded: the dense
  /// series, the prior line aligned to the period's days, and the tooltip.
  private func chart(_ insights: PeriodInsights) -> HeroSparklineView {
    let calendar = Calendar.current
    let today = Date()
    let range = HeroSparkline.range(for: insights.period, calendar: calendar)
    let span = HomeSparklineSeries.dayCount(in: range, calendar: calendar)
    let current = HomeSparklineSeries.cumulative(
      byDay: insights.byDay,
      kind: kind,
      periodRange: range,
      today: today,
      calendar: calendar
    )

    var prior: [Double]?
    var priorLabelText: String?
    if HeroComparison.priorAmount(kind: kind, insights: insights) != nil,
       let priorPeriod = DashboardPeriod.priorPeriod(for: insights.period) {
      let priorRange = dateRange(for: priorPeriod, calendar: calendar)
      let priorSeries = HomeSparklineSeries.cumulative(
        byDay: insights.priorByDay,
        kind: kind,
        periodRange: priorRange,
        today: priorRange.upperBound,
        calendar: calendar
      )
      prior = HomeSparklineSeries.aligned(priorSeries, count: span)
      priorLabelText = NomiComparisonCopy.priorLabel(period: insights.period, short: false, calendar: calendar)
    }

    let markerIndex = max(0, current.count - 1)
    let markerDay = calendar.date(byAdding: .day, value: markerIndex, to: range.lowerBound) ?? range.lowerBound
    let markerText = HeroSparkline.dayMonthText(markerDay, calendar: calendar)
    let tipDate = range.contains(today)
      ? String(localized: "Today, \(markerText)", bundle: .module)
      : markerText
    let ticks = HeroSparkline.tickLabels(for: insights.period, calendar: calendar)

    return HeroSparklineView(
      current: current,
      prior: prior,
      span: span,
      tipMinor: Int(current.last ?? 0),
      tipDate: tipDate,
      startLabel: ticks.first,
      endLabel: ticks.last,
      priorLabel: priorLabelText,
      accessibilityLabel: kind == .spent
        ? String(localized: "Spending this period", bundle: .module)
        : String(localized: "Income this period", bundle: .module),
      accessibilityValue: HeroSparkline.accessibilityValue(byDay: insights.byDay, kind: kind, calendar: calendar)
    )
  }

  private func priorLabel(for insights: PeriodInsights) -> String {
    NomiComparisonCopy.priorLabel(period: insights.period, short: false, calendar: Calendar.current)
  }

  private func animateIn() {
    displayedMinor = HeroCountUp.initialDisplayValue(target: targetMinor, reduceMotion: reduceMotion)
    guard !reduceMotion else { return }
    withAnimation(.easeOut(duration: 0.8)) {
      displayedMinor = targetMinor
    }
  }
}

/// Whether the hero figure starts its count-up from zero or renders the
/// final value immediately. Pulled out as a pure function so the
/// reduce-motion rule (done-when: "reduce-motion renders final state with no
/// count-up") is testable without driving a real animation.
enum HeroCountUp {
  static func initialDisplayValue(target: Int, reduceMotion: Bool) -> Int {
    reduceMotion ? target : 0
  }
}

/// The one read-only chip on the hero: dark glass, 26 pt high, 12/500 white. It
/// is text, not a button, and has no chevron. The arrow shows the direction.
private struct HeroComparisonChip: View {
  let chip: HeroComparison.Chip
  /// At accessibility sizes (S1b step 6) the words wrap onto as many lines as they
  /// need, and nothing is cut. At the standard sizes the chip stays one line.
  var wraps: Bool = false

  var body: some View {
    HStack(spacing: 6) {
      if let direction = chip.direction {
        Image(systemName: direction == .up ? "arrow.up" : "arrow.down")
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
      }
      Text(chip.text)
        .nomiTextStyle(.heroChip)
        .fixedSize(horizontal: false, vertical: wraps)
    }
    .foregroundStyle(NomiColor.heroText)
    .lineLimit(wraps ? nil : 1)
    .minimumScaleFactor(wraps ? 1 : 0.75)
    .padding(.horizontal, 10)
    .frame(minHeight: 26)
    .nomiGlass(.heroControl, in: Capsule())
  }
}

#Preview("Hero · spent, with prior") {
  HeroTotalCard(
    figures: .loaded(
      PeriodInsights(
        period: .month(year: 2026, month: 11),
        debitMinor: 35_318_00,
        creditMinor: 38_500_00,
        netMinor: 3_182_00,
        priorDebitMinor: 50_173_00,
        priorCreditMinor: 55_000_00,
        transactionCount: 74,
        byDay: [
          DayBucket(id: Date(timeIntervalSince1970: 1_793_500_800), debitMinor: 2_000_00),
          DayBucket(id: Date(timeIntervalSince1970: 1_793_673_600), debitMinor: 1_500_00),
        ],
        byCategory: [],
        topMerchants: [],
        needsReviewCount: 0,
        uncategorizedCount: 0
      )
    ),
    period: .month(year: 2026, month: 11),
    kind: .constant(.spent)
  )
  .padding(20)
  .background(NomiHeroGradient.gradient(height: 504, safeTop: 54))
  .preferredColorScheme(.light)
}

#Preview("Hero · loading") {
  HeroTotalCard(figures: .loading, period: .month(year: 2026, month: 11), kind: .constant(.spent))
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
    .preferredColorScheme(.light)
}

#Preview("Hero · unavailable") {
  HeroTotalCard(figures: .unavailable, period: .month(year: 2026, month: 11), kind: .constant(.income))
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
    .preferredColorScheme(.light)
}
