import NomiCore
import NomiPreview
import SwiftUI

/// The hero total's prior-period comparison. A pure calculation so the
/// increase/decrease framing is unit-testable without a live store.
enum HeroDelta {
  struct Result: Equatable {
    let percent: Double
    let isIncrease: Bool
  }

  /// `nil` when there is no comparable prior period, or the prior period was
  /// zero (a percentage change against zero is undefined, not "infinite%").
  static func compute(current: Int, prior: Int?) -> Result? {
    guard let prior, prior != 0 else { return nil }
    let percent = Double(current - prior) / Double(abs(prior))
    return Result(percent: percent, isIncrease: current >= prior)
  }

  static func percentText(_ percent: Double) -> String {
    let whole = Int((abs(percent) * 100).rounded())
    return "\(whole)%"
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

/// The two nested tiles inside the accent-filled hero card (`nomi.md`
/// "UI direction — v4"). Pulled out as a pure function, same reasoning as
/// `HeroDelta`/`HeroCountUp` above: this package's `swift test` runner has no
/// view-inspection library, so what the card is supposed to show is tested as
/// data rather than by rendering.
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

/// Card 1: the period's spend total against the prior period, now
/// accent-filled with two nested Income/Expenses tiles and `NomiGlow` — the
/// v4 change U9 specified but never wired up (`nomi-ui-reference-comparison.md`
/// §3). The AC is explicit that the headline figure — and only this figure on
/// the dashboard — uses PROPORTIONAL digits (`NomiTextStyle.dashboardHeroTotal`,
/// a plain custom font, not `TabularFigures`); every ranked list and axis tick
/// elsewhere uses the tabular helper instead.
///
/// Deliberately not `DashboardCard`: that shell is contractually `#212121`
/// per U9's own done-when, so this card builds its own accent-filled
/// container instead of touching that shared shell's contract.
public struct HeroTotalCard: View {
  public let insights: PeriodInsights

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var displayedMinor: Int

  public init(insights: PeriodInsights) {
    self.insights = insights
    _displayedMinor = State(initialValue: insights.debitMinor)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text("Spent this period")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textPrimary.opacity(0.7))
        Text(NomiFormatters.amountString(minor: displayedMinor))
          .nomiTextStyle(.dashboardHeroTotal)
          .foregroundStyle(NomiColor.textPrimary)
          .contentTransition(.numericText(value: Double(displayedMinor)))
        deltaView
      }
      tilesRow
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.accent)
    .nomiCornerRadius(NomiRadius.card)
    .nomiGlow()
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

  @ViewBuilder
  private var deltaView: some View {
    if let delta = HeroDelta.compute(current: insights.debitMinor, prior: insights.priorDebitMinor) {
      Text("\(delta.isIncrease ? "▲" : "▼") \(HeroDelta.percentText(delta.percent)) vs last period")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textPrimary.opacity(0.7))
    } else {
      Text("No prior period to compare")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textPrimary.opacity(0.7))
    }
  }

  // At accessibility Dynamic Type sizes the tiles stack instead of fighting
  // each other for horizontal space, same rule as `TransactionRow`.
  private var tilesRow: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: NomiSpacing.xs) {
          ForEach(HeroIncomeExpense.tiles(for: insights), id: \.title) { tile in
            tileView(tile)
          }
        }
      } else {
        HStack(spacing: NomiSpacing.xs) {
          ForEach(HeroIncomeExpense.tiles(for: insights), id: \.title) { tile in
            tileView(tile)
          }
        }
      }
    }
  }

  private func tileView(_ tile: HeroIncomeExpense.Tile) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text(tile.title)
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textPrimary.opacity(0.7))
      Text(tile.amountText)
        .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 14))
        .foregroundStyle(NomiColor.textPrimary)
    }
    .padding(NomiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.glassFill)
    .overlay(
      RoundedRectangle(cornerRadius: NomiRadius.tile, style: NomiRadius.cardSheetStyle)
        .stroke(NomiColor.glassHairline, lineWidth: 1)
    )
    .nomiCornerRadius(NomiRadius.tile)
  }
}

#Preview("Hero total — default, dark") {
  HeroTotalCard(insights: PeriodInsights(
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
  ))
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero total — no prior period, dark") {
  HeroTotalCard(insights: PeriodInsights(
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
  ))
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Hero total — accessibility 3, dark") {
  HeroTotalCard(insights: PeriodInsights(
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
  ))
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
