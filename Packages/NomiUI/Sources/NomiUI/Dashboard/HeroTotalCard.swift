import NomiCore
import NomiPreview
import SwiftUI

/// The hero total's prior-period comparison. A pure calculation so the
/// increase/decrease framing is unit-testable without a live store.
enum HeroDelta {
  struct Result: Equatable {
    let deltaMinor: Int
    let isIncrease: Bool
  }

  /// `nil` only when there is no comparable prior period at all — v5: a zero
  /// prior is a real prior now, so `compute(1000, 0)` is `+1000`, not `nil`;
  /// the delta is simply the whole current figure.
  static func compute(current: Int, prior: Int?) -> Result? {
    guard let prior else { return nil }
    return Result(deltaMinor: current - prior, isIncrease: current >= prior)
  }

  /// The chip's copy (HM1, the artboard): "up ₹6,420 vs last period". The
  /// direction is a word, so it reads without colour.
  ///
  /// Whole-rupee deltas drop the ".00", as `ReportsPeriod.changeCopy` does, so
  /// Home and Insights state the same change the same way (D27).
  static func chipCopy(_ result: Result) -> String {
    let direction = result.isIncrease ? "up" : "down"
    var amount = NomiFormatters.amountString(minor: abs(result.deltaMinor))
    if abs(result.deltaMinor) % 100 == 0, amount.hasSuffix(".00") {
      amount.removeLast(3)
    }
    return "\(direction) \(amount) vs last period"
  }

  /// The delta the chip may state, or `nil` when it has nothing to say.
  ///
  /// Hidden when there is no prior period, and when the delta is exactly zero.
  /// The zero case covers zero spend against a zero prior (the first-run Home,
  /// HomeFirstRun artboard: no chip) and an unchanged figure against a real
  /// prior. Neither has a direction to state, so the chip never prints
  /// "up ₹0.00". The test is on minor units, not on the formatted string, so a
  /// one-paisa change is still a change and is never rounded away.
  static func visibleDelta(current: Int, prior: Int?) -> Result? {
    guard let delta = compute(current: current, prior: prior), delta.deltaMinor != 0 else {
      return nil
    }
    return delta
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

/// The two figures behind the hero's income/expenses caption line (v5: the
/// nested tiles became text, but the pure source of both strings survives
/// unchanged). Pulled out as a pure function, same reasoning as `HeroDelta`/
/// `HeroCountUp` above: this package's `swift test` runner has no
/// view-inspection library, so what the line is supposed to show is tested
/// as data rather than by rendering.
enum HeroIncomeExpense {
  struct Tile: Equatable {
    let title: String
    let amountText: String
  }

  static func tiles(for insights: PeriodInsights) -> [Tile] {
    [
      Tile(title: "Income", amountText: NomiFormatters.amountString(minor: insights.creditMinor)),
      Tile(title: "Expenses", amountText: NomiFormatters.amountString(minor: insights.debitMinor)),
    ]
  }
}

/// The Home hero's figures (HM1; the approved Main artboard): the spent
/// amount on the hero, a "Spent" and "Income" label row above it, one
/// read-only delta chip, and the chart with its two day ticks. Layout sits
/// inside `NomiHeroScaffold`, which places the hero at 110 pt and the sheet
/// at 332 pt. The heights below reproduce the artboard (label 110, amount
/// 130, chip 194, chart 232, ticks 304). The count-up is kept from v5.
public struct HeroTotalCard: View {
  public let insights: PeriodInsights

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var displayedMinor: Int

  public init(insights: PeriodInsights) {
    self.insights = insights
    _displayedMinor = State(initialValue: insights.debitMinor)
  }

  public var body: some View {
    let ticks = HeroSparkline.tickLabels(for: insights.period)
    VStack(alignment: .leading, spacing: 0) {
      HeroLabelRow(income: incomeText)
        .padding(.bottom, 2)
      NomiAmountText(
        minor: displayedMinor,
        context: .hero,
        style: .heroAmount,
        accessibilityLabel: "Spent in \(DashboardPeriod.label(for: insights.period)), \(NomiFormatters.amountString(minor: insights.debitMinor))"
      )
      .contentTransition(.numericText(value: Double(displayedMinor)))
      chipRow
      NomiHeroChartSlot {
        VStack(spacing: 0) {
          HeroSparklineView(byDay: insights.byDay, range: HeroSparkline.range(for: insights.period))
          HStack {
            Text(ticks.first)
            Spacer(minLength: 8)
            Text(ticks.last)
          }
          .nomiTextStyle(.micro)
          .foregroundStyle(NomiColor.inkDeep)
          .padding(.top, 8)
          .accessibilityHidden(true)
        }
        .padding(.top, 12)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .onAppear { animateIn() }
    .onChange(of: insights.debitMinor) { _, _ in animateIn() }
  }

  private func animateIn() {
    displayedMinor = HeroCountUp.initialDisplayValue(target: insights.debitMinor, reduceMotion: reduceMotion)
    guard !reduceMotion else { return }
    withAnimation(.easeOut(duration: 0.8)) {
      displayedMinor = insights.debitMinor
    }
  }

  private var incomeText: String {
    HeroIncomeExpense.tiles(for: insights).first { $0.title == "Income" }?.amountText ?? ""
  }

  /// The chip keeps its 26 pt row when there is nothing to state, so the chart
  /// stays at 232 pt. A zero spend against a real prior period still shows its
  /// "down" chip. See `HeroDelta.visibleDelta` for the hidden cases.
  private var chipRow: some View {
    Group {
      if let delta = HeroDelta.visibleDelta(current: insights.debitMinor, prior: insights.priorDebitMinor) {
        HeroDeltaChip(text: HeroDelta.chipCopy(delta))
      } else {
        Color.clear.frame(height: 26)
      }
    }
    .padding(.top, 8)
  }
}

/// The hero's state when the period's figures did not load (HM1, the LoadFailed
/// artboard): "₹—" and "Income —", no chip and no chart. The reserved space
/// matches `HeroTotalCard`, so the sheet still starts at 332 pt.
struct HeroUnavailableCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HeroLabelRow(income: "—")
        .padding(.bottom, 2)
      Text("₹—")
        .nomiTextStyle(.heroAmount)
        .foregroundStyle(NomiColor.heroText)
        .lineLimit(1)
        .accessibilityLabel("Spending unavailable")
      Color.clear
        .frame(height: 26)
        .padding(.top, 8)
      NomiHeroChartSlot {
        Color.clear
          .frame(height: 64 + 12 + 8 + 16)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// "Spent" on the left and "Income <amount>" on the right, both 13/500
/// `heroTextSecondary`.
private struct HeroLabelRow: View {
  let income: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("Spent")
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Spacer(minLength: 8)
      Text("Income \(income)")
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .nomiTextStyle(.subhead)
    .foregroundStyle(NomiColor.heroTextSecondary)
    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
  }
}

/// The one read-only chip on the hero: dark glass, 26 pt high, 12/500 white. It
/// is text, not a button, and has no chevron.
private struct HeroDeltaChip: View {
  let text: String

  var body: some View {
    Text(text)
      .nomiTextStyle(.heroChip)
      .foregroundStyle(NomiColor.heroText)
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .padding(.horizontal, 10)
      .frame(minHeight: 26)
      .nomiGlass(.heroControl, in: Capsule())
  }
}

#Preview("Hero total · default") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 11),
      debitMinor: 64_824_24,
      creditMinor: 38_500_00,
      netMinor: -26_324_24,
      priorDebitMinor: 58_404_00,
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
  )
  .padding(20)
  .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
  .preferredColorScheme(.light)
}

#Preview("Hero total · no prior period") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 11),
      debitMinor: 12_000_00,
      creditMinor: 20_000_00,
      netMinor: 8_000_00,
      priorDebitMinor: nil,
      priorCreditMinor: nil,
      transactionCount: 9,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )
  )
  .padding(20)
  .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
  .preferredColorScheme(.light)
}

#Preview("Hero total · accessibility 3") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 11),
      debitMinor: 64_824_24,
      creditMinor: 38_500_00,
      netMinor: -26_324_24,
      priorDebitMinor: 58_404_00,
      priorCreditMinor: 55_000_00,
      transactionCount: 74,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )
  )
  .padding(20)
  .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}

#Preview("Hero unavailable") {
  HeroUnavailableCard()
    .padding(20)
    .background(NomiHeroGradient.gradient(height: 356, safeTop: 54))
    .preferredColorScheme(.light)
}
