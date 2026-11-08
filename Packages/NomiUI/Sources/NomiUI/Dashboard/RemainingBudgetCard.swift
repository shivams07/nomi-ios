import NomiCore
import SwiftUI

/// Card 4 (HM2, Main artboard): what is left of this month's budget, the
/// "spent of budgeted" caption and the shared progress bar. It reads
/// `BudgetTotals` from `BudgetsLogic.swift`, so the figures can never disagree
/// with the Budgets screen.
///
/// Not `public`, same as `DashboardCard` next door, because its `state` takes
/// `DashboardWiring.BudgetModuleState`, and `DashboardWiring` is deliberately
/// internal (it is wiring, not API).
///
/// `DashboardView` wraps the whole card in `NavigationLink(value:
/// DashboardRoute.budgets)`. That link, not this file, is the "whole card is a
/// NavigationLink" contract.
struct RemainingBudgetCard: View {
  let state: DashboardWiring.BudgetModuleState
  /// Kept for the unchanged init. The Home card draws no pace line any more, so
  /// the date no longer changes what is drawn.
  let referenceDate: Date

  init(state: DashboardWiring.BudgetModuleState, referenceDate: Date = Date()) {
    self.state = state
    self.referenceDate = referenceDate
  }

  var body: some View {
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
    let over = RemainingBudgetText.isOver(remainingMinor: totals.remainingMinor)
    return VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      titleRow
      HStack(alignment: .firstTextBaseline, spacing: NomiSpacing.xs) {
        if over {
          DashboardAmountText(
            minor: -totals.remainingMinor,
            style: .displayValue,
            colour: NomiColor.error
          )
          Text("over")
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.error)
        } else {
          NomiAmountText(minor: totals.remainingMinor, style: .displayValue)
        }
      }
      Text(RemainingBudgetText.caption(spentMinor: totals.spentMinor, budgetMinor: totals.budgetMinor))
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
      NomiProgressBar(fraction: totals.fraction)
        .padding(.top, NomiSpacing.xxs)
    }
    .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      RemainingBudgetText.accessibilityLabel(remainingMinor: totals.remainingMinor, budgetMinor: totals.budgetMinor)
    )
  }

  private var titleRow: some View {
    HStack(spacing: NomiSpacing.xs) {
      Text("Remaining budget")
        .nomiTextStyle(.label)
        .foregroundStyle(NomiColor.dayHeader)
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityHidden(true)
    }
  }

  /// No budgets set yet. The prompt and its chevron are unchanged in meaning;
  /// only the type and colour tokens moved.
  private var promptContent: some View {
    HStack(spacing: NomiSpacing.xs) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Set a monthly budget")
          .nomiTextStyle(.headline)
          .foregroundStyle(NomiColor.ink)
        Text("Nomi warns you as you approach it")
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      Spacer(minLength: NomiSpacing.xs)
      Image(systemName: "chevron.right")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .foregroundStyle(NomiColor.inkSecondary)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The Remaining budget card's wording and the over-budget rule, pure so the
/// tests can reach them.
enum RemainingBudgetText {
  /// Over means strictly below zero. Exactly zero left is not over.
  static func isOver(remainingMinor: Int) -> Bool {
    remainingMinor < 0
  }

  static func caption(spentMinor: Int, budgetMinor: Int) -> String {
    "\(NomiFormatters.amountString(minor: spentMinor)) spent of \(NomiFormatters.amountString(minor: budgetMinor)) budgeted"
  }

  /// The card is one element. Its label carries the same figures as the
  /// artboard's: what is left, or how far over, and the budget.
  static func accessibilityLabel(remainingMinor: Int, budgetMinor: Int) -> String {
    let budget = NomiFormatters.amountString(minor: budgetMinor)
    if isOver(remainingMinor: remainingMinor) {
      return "Remaining budget: \(NomiFormatters.amountString(minor: -remainingMinor)) over. Budget \(budget)."
    }
    return "Remaining budget: \(NomiFormatters.amountString(minor: remainingMinor)) left of \(budget)"
  }
}

#Preview("Remaining budget · under budget") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 80000_00, spentMinor: 64824_00, remainingMinor: 15175_76, fraction: 0.81)
  ))
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Remaining budget · over budget") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 18000_00, spentMinor: 18600_00, remainingMinor: -600_00, fraction: 1.033)
  ))
  .padding()
  .background(NomiColor.ground)
  .preferredColorScheme(.light)
}

#Preview("Remaining budget · prompt") {
  RemainingBudgetCard(state: .prompt)
    .padding()
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

#Preview("Remaining budget · accessibility 3") {
  RemainingBudgetCard(state: .remaining(
    BudgetTotals.Totals(budgetMinor: 80000_00, spentMinor: 64824_00, remainingMinor: 15175_76, fraction: 0.81)
  ))
  .padding()
  .background(NomiColor.ground)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}
