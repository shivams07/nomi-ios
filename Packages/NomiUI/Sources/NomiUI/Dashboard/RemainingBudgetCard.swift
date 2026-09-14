import NomiCore
import SwiftUI

/// Card 4 (v5 `nomi-ui-refresh` §Home). Reads `BudgetTotals`/`BudgetPace`
/// from `BudgetsLogic.swift` (M3) so the ring/pace line here can never
/// disagree with the Budgets screen's own gauge and pace cards.
///
/// `DashboardView` wraps the whole card in `NavigationLink(value:
/// DashboardRoute.budgets)` — that link, not this file, is the "whole card is
/// a NavigationLink" contract, since `DashboardRoute` and the gate that
/// checks for it both live in `DashboardView.swift`.
public struct RemainingBudgetCard: View {
  public let state: DashboardWiring.BudgetModuleState
  public let referenceDate: Date

  public init(state: DashboardWiring.BudgetModuleState, referenceDate: Date = Date()) {
    self.state = state
    self.referenceDate = referenceDate
  }

  public var body: some View {
    DashboardCard {
      switch state {
      case .remaining(let totals):
        remainingContent(totals: totals)
      case .prompt:
        promptContent
      }
    }
  }

  private func remainingContent(totals: BudgetTotals.Totals) -> some View {
    let pace = BudgetPace.assess(
      spentFraction: totals.fraction,
      elapsedFraction: RemainingBudgetPace.elapsedFraction(referenceDate: referenceDate)
    )
    return HStack(spacing: NomiSpacing.sm) {
      ZStack {
        NomiRingGauge(fraction: totals.fraction, lineWidth: 4)
          .frame(width: 36, height: 36)
        Text(RemainingBudgetPercent.text(totals.fraction))
          .font(TabularFigures.font(name: NomiFont.interRegular, size: 11))
          .foregroundStyle(NomiColor.textPrimary)
      }
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xxs) {
          Text(NomiFormatters.amountString(minor: totals.remainingMinor))
            .nomiTextStyle(.title)
            .foregroundStyle(NomiColor.textPrimary)
          Text("remaining")
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.textTertiary)
        }
        Text(pace.line(overByMinor: -totals.remainingMinor))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer(minLength: 0)
    }
  }

  private var promptContent: some View {
    HStack {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text("Set a monthly budget")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        Text("Nomi warns you as you approach it")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      Spacer(minLength: NomiSpacing.xs)
      Image(systemName: "chevron.right")
        .foregroundStyle(NomiColor.textTertiary)
    }
  }
}

/// The small ring's inline caption — "34%", no "used" suffix (that belongs to
/// the Budgets screen's own larger gauge card).
enum RemainingBudgetPercent {
  static func text(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded()))%"
  }
}

/// How far through the month `referenceDate` sits — the same rule
/// `BudgetsScreen`'s own private `elapsedFraction` computes. Duplicated
/// rather than shared: `BudgetsLogic.swift` is M3's file, and this unit does
/// not touch `Budgets/**`.
enum RemainingBudgetPace {
  static func elapsedFraction(referenceDate: Date, calendar: Calendar = .current) -> Double {
    guard let daysInMonth = calendar.range(of: .day, in: .month, for: referenceDate)?.count, daysInMonth > 0 else {
      return 0
    }
    let today = calendar.component(.day, from: referenceDate)
    return Double(today) / Double(daysInMonth)
  }
}

#Preview("Remaining budget — under pace, dark") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 18000_00, spentMinor: 6200_00, remainingMinor: 11800_00, fraction: 0.34)
  ))
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Remaining budget — over budget, dark") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 18000_00, spentMinor: 18600_00, remainingMinor: -600_00, fraction: 1.033)
  ))
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Remaining budget — zero budgets, prompt, dark") {
  RemainingBudgetCard(state: .prompt)
    .padding()
    .background(NomiColor.surfaceCanvas)
    .preferredColorScheme(.dark)
}

#Preview("Remaining budget — accessibility 3, dark") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 18000_00, spentMinor: 6200_00, remainingMinor: 11800_00, fraction: 0.34)
  ))
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
