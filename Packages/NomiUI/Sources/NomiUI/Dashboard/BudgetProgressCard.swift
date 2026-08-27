import NomiCore
import SwiftUI

/// Card 8 (v5): monthly budget progress, one row per budgeted category,
/// using the shared `NomiProgressBar` (its own 90%-over-budget colour switch
/// applies here unmodified). The AC is explicit that this module is rendered
/// ONLY when at least one budget exists — that gating lives in
/// `DashboardView`/`DashboardWiring`, not here; this view always renders
/// whatever it is given, so it must never be called with an empty array.
public struct BudgetProgressCard: View {
  public let items: [BudgetProgress]

  public init(items: [BudgetProgress]) {
    self.items = items
  }

  public var body: some View {
    DashboardCard {
      VStack(alignment: .leading, spacing: NomiSpacing.sm) {
        Text("Budgets")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        VStack(spacing: NomiSpacing.sm) {
          ForEach(items) { item in
            VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
              HStack(spacing: NomiSpacing.xs) {
                Circle()
                  .fill(paletteSlot(item.paletteSlot))
                  .frame(width: 8, height: 8)
                Text(item.categoryName)
                  .nomiTextStyle(.body)
                  .foregroundStyle(NomiColor.textPrimary)
                  .lineLimit(1)
                Spacer(minLength: NomiSpacing.xs)
                Text(Self.line(for: item))
                  .font(TabularFigures.font(name: NomiFont.interRegular, size: 13))
                  .foregroundStyle(NomiColor.textSecondary)
              }
              NomiProgressBar(fraction: item.fraction)
            }
          }
        }
      }
    }
  }

  static func line(for item: BudgetProgress) -> String {
    "\(NomiFormatters.amountString(minor: item.spentMinor)) of \(NomiFormatters.amountString(minor: item.budgetMinor))"
  }
}

#Preview("Budget progress — default, dark") {
  BudgetProgressCard(items: [
    BudgetProgress(id: UUID(), categoryName: "Food & Dining", paletteSlot: 0, budgetMinor: 5000_00, spentMinor: 4750_00, fraction: 0.95, periodKey: "2026-08"),
    BudgetProgress(id: UUID(), categoryName: "Shopping", paletteSlot: 1, budgetMinor: 8000_00, spentMinor: 3200_00, fraction: 0.4, periodKey: "2026-08"),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .preferredColorScheme(.dark)
}

#Preview("Budget progress — accessibility 3, dark") {
  BudgetProgressCard(items: [
    BudgetProgress(id: UUID(), categoryName: "Food & Dining", paletteSlot: 0, budgetMinor: 5000_00, spentMinor: 4750_00, fraction: 0.95, periodKey: "2026-08"),
  ])
  .padding()
  .background(NomiColor.surfaceCanvas)
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
