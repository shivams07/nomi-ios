import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Budgets page (U12, v5 new). Category-level only — no whole-app cap
/// exists or should be added (spec Assumptions). Reads `Design/**`. Must not
/// edit it. The over-90% treatment reuses `NomiProgressBar`'s existing token
/// rather than inventing a second red.
public struct BudgetsScreen: View {
  public let budgetStore: BudgetStore
  public let insightsStore: InsightsStore

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var budgetRows: [NomiCore.Budget]
  @State private var editingCategory: NomiCore.Category?
  @State private var isAddingBudget = false
  @State private var now = Date()

  public init(budgetStore: BudgetStore, insightsStore: InsightsStore) {
    self.budgetStore = budgetStore
    self.insightsStore = insightsStore
  }

  private var progress: [BudgetProgress] {
    let (year, month) = BudgetPeriod.current(from: now)
    return (try? insightsStore.budgetProgress(year: year, month: month)) ?? []
  }

  private var budgetedCategoryIDs: Set<UUID> {
    Set(budgetRows.map(\.categoryID))
  }

  private var unbudgetedCategories: [NomiCore.Category] {
    categories.filter { !budgetedCategoryIDs.contains($0.id) }
  }

  private func amountMinor(for categoryID: UUID) -> Int {
    budgetRows.first { $0.categoryID == categoryID }?.amountMinor ?? 0
  }

  public var body: some View {
    List {
      if progress.isEmpty {
        emptyStateSection
      } else {
        Section("Budgets") {
          ForEach(progress) { item in
            row(for: item)
              .contentShape(Rectangle())
              .onTapGesture {
                if let category = categories.first(where: { $0.id == item.id }) {
                  editingCategory = category
                }
              }
          }
        }
      }
      Section {
        Button("Add Budget") { isAddingBudget = true }
          .disabled(unbudgetedCategories.isEmpty)
      }
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Budgets")
    .sheet(item: $editingCategory) { category in
      BudgetEditorSheet(
        budgetStore: budgetStore,
        category: category,
        availableCategories: [],
        currentAmountMinor: amountMinor(for: category.id)
      )
    }
    .sheet(isPresented: $isAddingBudget) {
      BudgetEditorSheet(
        budgetStore: budgetStore,
        category: nil,
        availableCategories: unbudgetedCategories,
        currentAmountMinor: 0
      )
    }
  }

  private var emptyStateSection: some View {
    Section {
      VStack(alignment: .leading, spacing: NomiSpacing.xs) {
        Text("No budgets yet")
          .nomiTextStyle(.title)
          .foregroundStyle(NomiColor.textPrimary)
        Text("A budget tracks how much you spend in a category each month and warns you as you approach the limit. Add one to get started.")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
      .padding(.vertical, NomiSpacing.xs)
    }
  }

  private func row(for item: BudgetProgress) -> some View {
    let isAtThreshold = BudgetRowEmphasis.isAtOrAboveThreshold(item)
    return VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      HStack(spacing: NomiSpacing.xs) {
        Circle()
          .fill(paletteSlot(item.paletteSlot))
          .frame(width: 8, height: 8)
        Text(item.categoryName)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
          .lineLimit(1)
        Spacer(minLength: NomiSpacing.xs)
        if isAtThreshold {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(NomiColor.overBudget)
        }
        Text(BudgetRowSummary.line(for: item))
          .font(TabularFigures.font(name: NomiFont.interRegular, size: 13))
          .fontWeight(isAtThreshold ? .semibold : .regular)
          .foregroundStyle(NomiColor.textSecondary)
      }
      NomiProgressBar(fraction: item.fraction)
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }
}

/// The row's spend/budget line — separate from `BudgetProgressCard.line(for:)`
/// (Dashboard/**, not owned by this unit) since duplicating that private
/// formatting call isn't available across files without making it public,
/// and this page's row layout differs (it also needs the emphasis glyph).
enum BudgetRowSummary {
  static func line(for item: BudgetProgress) -> String {
    "\(NomiFormatters.amountString(minor: item.spentMinor)) of \(NomiFormatters.amountString(minor: item.budgetMinor))"
  }
}

#Preview("Budgets — no budgets set, dark") {
  NavigationStack {
    BudgetsScreen(budgetStore: FakeBudgetStore(budgets: []), insightsStore: BudgetsPreviewSupport.makeInsightsStore(progress: []))
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: []))
  .preferredColorScheme(.dark)
}

#Preview("Budgets — mixed thresholds, dark") {
  NavigationStack {
    BudgetsScreen(
      budgetStore: FakeBudgetStore(budgets: BudgetsPreviewSupport.sampleBudgets),
      insightsStore: BudgetsPreviewSupport.makeInsightsStore()
    )
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: BudgetsPreviewSupport.sampleBudgets))
  .preferredColorScheme(.dark)
}
