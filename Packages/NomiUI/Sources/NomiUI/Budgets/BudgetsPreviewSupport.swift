import Foundation
import NomiCore
import SwiftData

/// Preview-only fixtures for the Budgets page. `FakeInsightsStore`'s real
/// category/transaction matching (from `NomiPreview.PreviewData`) can't be
/// relied on to land at exact fractions (0.4 / 0.9 / 1.3 / 0.0) — the AC
/// needs those four states precisely, so `FixedBudgetProgressInsightsStore`
/// returns a fixed array instead of computing one. Same "fresh, local fixture
/// rather than depend on shared preview data" reasoning as
/// `EntryRulesPreviewSupport` and `ImportPreviewSupport`.
enum BudgetsPreviewSupport {
  static let foodID = UUID()
  static let shoppingID = UUID()
  static let transportID = UUID()
  static let billsID = UUID()

  static func makeCategories() -> [NomiCore.Category] {
    [
      NomiCore.Category(id: foodID, name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0),
      NomiCore.Category(id: shoppingID, name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: true, sortIndex: 1),
      NomiCore.Category(id: transportID, name: "Transport", symbolName: "car", paletteSlot: 2, isSystem: false, sortIndex: 2),
      NomiCore.Category(id: billsID, name: "Bills & Utilities", symbolName: "bolt", paletteSlot: 3, isSystem: true, sortIndex: 3),
    ]
  }

  static let sampleBudgets: [NomiCore.Budget] = [
    Budget(categoryID: foodID, amountMinor: 5000_00),
    Budget(categoryID: shoppingID, amountMinor: 8000_00),
    Budget(categoryID: transportID, amountMinor: 2000_00),
    Budget(categoryID: billsID, amountMinor: 3000_00),
  ]

  static let sampleProgress: [BudgetProgress] = [
    BudgetProgress(id: foodID, categoryName: "Food & Dining", paletteSlot: 0, budgetMinor: 5000_00, spentMinor: 2000_00, fraction: 0.4, periodKey: "2026-08"),
    BudgetProgress(id: shoppingID, categoryName: "Shopping", paletteSlot: 1, budgetMinor: 8000_00, spentMinor: 7200_00, fraction: 0.9, periodKey: "2026-08"),
    BudgetProgress(id: transportID, categoryName: "Transport", paletteSlot: 2, budgetMinor: 2000_00, spentMinor: 2600_00, fraction: 1.3, periodKey: "2026-08"),
    BudgetProgress(id: billsID, categoryName: "Bills & Utilities", paletteSlot: 3, budgetMinor: 3000_00, spentMinor: 0, fraction: 0.0, periodKey: "2026-08"),
  ]

  @MainActor
  static func makeContainer(budgets: [NomiCore.Budget]) -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Category.self, NomiCore.Budget.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    for category in makeCategories() {
      container.mainContext.insert(category)
    }
    for budget in budgets {
      container.mainContext.insert(Budget(categoryID: budget.categoryID, amountMinor: budget.amountMinor))
    }
    return container
  }

  @MainActor
  static func makeInsightsStore(progress: [BudgetProgress] = sampleProgress) -> FixedBudgetProgressInsightsStore {
    FixedBudgetProgressInsightsStore(progress: progress)
  }
}

/// An `InsightsStore` that only actually implements `budgetProgress` — the
/// only method `BudgetsScreen` calls. Everything else throws, which is
/// deliberate: a preview relying on a method this store doesn't back would
/// rather fail loudly (an empty state) than silently return convincing-looking
/// zeros.
@MainActor
final class FixedBudgetProgressInsightsStore: InsightsStore {
  private let progress: [BudgetProgress]

  init(progress: [BudgetProgress]) {
    self.progress = progress
  }

  func insights(for period: InsightPeriod) throws -> PeriodInsights {
    throw NotImplementedForPreview()
  }

  func trend(months: Int) throws -> [MonthBucket] { [] }

  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }

  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    progress
  }

  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}

private struct NotImplementedForPreview: Error {}
