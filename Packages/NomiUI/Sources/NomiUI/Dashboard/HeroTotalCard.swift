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

/// Card 3 (v5 `nomi-ui-refresh` §Home): the period's spend total, flush on
/// the ground — deliberately not `DashboardCard`, no accent fill, no glow
/// modifier. Centred: caption, headline figure, delta, the cumulative
/// sparkline, then one income/expenses caption line. The AC is explicit that
/// the headline figure — and only this figure on the dashboard — uses
/// PROPORTIONAL digits (`NomiTextStyle.dashboardHeroTotal`, a plain custom
/// font, not `TabularFigures`); every ranked list and axis tick elsewhere
/// uses the tabular helper instead.
public struct HeroTotalCard: View {
  public let insights: PeriodInsights
  public let periodLabel: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var displayedMinor: Int

  public init(insights: PeriodInsights, periodLabel: String) {
    self.insights = insights
    self.periodLabel = periodLabel
    _displayedMinor = State(initialValue: insights.debitMinor)
  }

  public var body: some View {
    VStack(spacing: NomiSpacing.sm) {
      VStack(spacing: NomiSpacing.xxs) {
        Text("Total spent in \(periodLabel)")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
        Text(NomiFormatters.amountString(minor: displayedMinor))
          .nomiTextStyle(.dashboardHeroTotal)
          .foregroundStyle(Color.white)
          .contentTransition(.numericText(value: Double(displayedMinor)))
        deltaView
      }
      HeroSparklineView(byDay: insights.byDay)
        .frame(maxWidth: .infinity)
      Text(incomeExpenseLine)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
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

  /// An absolute amount, as the reference — the glyph carries direction, no
  /// hue, so the caption stays tertiary regardless of increase or decrease.
  @ViewBuilder
  private var deltaView: some View {
    if let delta = HeroDelta.compute(current: insights.debitMinor, prior: insights.priorDebitMinor) {
      Text("\(delta.isIncrease ? "↑" : "↓") \(NomiFormatters.amountString(minor: abs(delta.deltaMinor))) vs last period")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    } else {
      Text("No prior period to compare")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
    }
  }

  private var incomeExpenseLine: String {
    HeroIncomeExpense.tiles(for: insights)
      .map { "\($0.title) \($0.amountText)" }
      .joined(separator: " · ")
  }
}

#Preview("Hero total — default, dark") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 8),
      debitMinor: 42_318_00,
      creditMinor: 60_000_00,
      netMinor: 17_682_00,
      priorDebitMinor: 38_000_00,
      priorCreditMinor: 55_000_00,
      transactionCount: 74,
      byDay: (0..<20).map { offset in
        DayBucket(
          id: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!,
          debitMinor: Int.random(in: 500...9000) * 100
        )
      },
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    ),
    periodLabel: "August 2026"
  )
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero total — no prior period, dark") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .allTime,
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
    ),
    periodLabel: "All time"
  )
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero total — sparkline with two buckets, dark") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 9),
      debitMinor: 3500_00,
      creditMinor: 5000_00,
      netMinor: 1500_00,
      priorDebitMinor: 3000_00,
      priorCreditMinor: 5000_00,
      transactionCount: 4,
      byDay: [
        DayBucket(id: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, debitMinor: 2000_00),
        DayBucket(id: Date(), debitMinor: 1500_00),
      ],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    ),
    periodLabel: "September 2026"
  )
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero total — accessibility 3, dark") {
  HeroTotalCard(
    insights: PeriodInsights(
      period: .month(year: 2026, month: 8),
      debitMinor: 42_318_00,
      creditMinor: 60_000_00,
      netMinor: 17_682_00,
      priorDebitMinor: 38_000_00,
      priorCreditMinor: 55_000_00,
      transactionCount: 74,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    ),
    periodLabel: "August 2026"
  )
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}

// No reduce-motion #Preview: EnvironmentValues.accessibilityReduceMotion is a
// read-only reflection of the system setting on this SDK (Xcode 16.2) — it
// cannot be overridden via `.environment(_:_:)`, only observed. The actual
// rule ("reduce-motion renders final state with no count-up") is covered by
// `HeroCountUp.initialDisplayValue` in HeroTotalCardTests instead.
