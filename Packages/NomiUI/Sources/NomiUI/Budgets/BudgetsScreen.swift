import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Budgets page (U12; v5 `ui-budgets` refresh, M3). Category-level only —
/// no whole-app cap exists or should be added (spec Assumptions). Reads
/// `Design/**`. Must not edit it. The gauge card's ring and the tiles' over
/// captions share `NomiRingGauge`/`BudgetRowEmphasis`'s 90% threshold and
/// `overBudget` token rather than inventing a second red; tiles carry no bar
/// of their own — the ring carries the aggregate.
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

  /// `nil` means the fetch threw — distinct from a legitimate zero-budgets
  /// month, which is `[]` and renders `emptyState`.
  private var progress: [BudgetProgress]? {
    let (year, month) = BudgetPeriod.current(from: now)
    do {
      return try insightsStore.budgetProgress(year: year, month: month)
    } catch {
      return nil
    }
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
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardToCard) {
        if let progress {
          if progress.isEmpty {
            emptyState
          } else if let totals = BudgetTotals.compute(progress) {
            paceCard(totals: totals)
            gaugeCard(totals: totals)
            categoryBudgetsSection(for: progress)
            addBudgetButton
          }
        } else {
          loadFailedState
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
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

  private var loadFailedState: some View {
    Text("Couldn't load budgets")
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.textTertiary)
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("No budgets yet")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text("A budget tracks how much you spend in a category each month and warns you as you approach the limit. Add one to get started.")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      addBudgetButton
        .padding(.top, NomiSpacing.xs)
    }
  }

  private var elapsedFraction: Double {
    let calendar = Calendar.current
    guard let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count else { return 0 }
    let today = calendar.component(.day, from: now)
    return Double(today) / Double(daysInMonth)
  }

  private func paceCard(totals: BudgetTotals.Totals) -> some View {
    let pace = BudgetPace.assess(spentFraction: totals.fraction, elapsedFraction: elapsedFraction)
    return DashboardCard {
      HStack(alignment: .top, spacing: NomiSpacing.xs) {
        Image(systemName: "sparkle")
          .foregroundStyle(NomiColor.textTertiary)
        Text(pace.line(overByMinor: -totals.remainingMinor))
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
      }
    }
  }

  private func gaugeCard(totals: BudgetTotals.Totals) -> some View {
    let daysLeft = BudgetDaysLeft.remaining(from: now)
    return DashboardCard {
      VStack(spacing: NomiSpacing.sm) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
            Text("Monthly")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            Text(BudgetPeriodText.monthRange(for: now))
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textPrimary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: NomiSpacing.xxs) {
            Text("Days left")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            Text("\(daysLeft) days")
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textPrimary)
          }
        }
        ZStack {
          NomiRingGauge(fraction: totals.fraction, lineWidth: 14)
            .frame(width: 140, height: 140)
          VStack(spacing: NomiSpacing.xxs) {
            Text("Left to spend")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
            Text(NomiFormatters.amountString(minor: totals.remainingMinor))
              .nomiTextStyle(.displayValue)
              .foregroundStyle(NomiColor.textPrimary)
            Text("\(Int((totals.fraction * 100).rounded()))% used")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
        }
      }
    }
  }

  private func categoryBudgetsSection(for progress: [BudgetProgress]) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      Text("Category budgets")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: NomiSpacing.sm) {
        ForEach(progress) { item in
          budgetTile(for: item)
            .contentShape(Rectangle())
            .onTapGesture {
              if let category = categories.first(where: { $0.id == item.id }) {
                editingCategory = category
              }
            }
        }
      }
    }
  }

  private func budgetTile(for item: BudgetProgress) -> some View {
    let caption = BudgetTileCaption.text(item.budgetMinor - item.spentMinor)
    let isAtThreshold = BudgetRowEmphasis.isAtOrAboveThreshold(item)
    return VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      NomiCategoryBadge(symbolName: item.symbolName, paletteSlot: item.paletteSlot, size: 40)
      Text(item.categoryName)
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .lineLimit(1)
      Text(NomiFormatters.amountString(minor: item.spentMinor))
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text(caption.text)
        .nomiTextStyle(.caption)
        .foregroundStyle(caption.isOver || isAtThreshold ? NomiColor.overBudget : NomiColor.textTertiary)
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRow)
    .nomiCornerRadius(NomiRadius.inset)
  }

  private var addBudgetButton: some View {
    Button {
      isAddingBudget = true
    } label: {
      Text("Add Budget")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, NomiSpacing.xs)
        .background(NomiColor.accent)
        .clipShape(Capsule(style: .continuous))
    }
    .disabled(unbudgetedCategories.isEmpty)
  }
}

/// The gauge card's date-range caption — "1 Sep – 30 Sep", the current
/// month's first and last day.
enum BudgetPeriodText {
  static func monthRange(for date: Date, calendar: Calendar = .current) -> String {
    guard
      let interval = calendar.dateInterval(of: .month, for: date),
      let lastDay = calendar.date(byAdding: DateComponents(day: -1), to: interval.end)
    else { return "" }
    return "\(NomiFormatters.dayMonth.string(from: interval.start)) – \(NomiFormatters.dayMonth.string(from: lastDay))"
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

private struct BudgetsScreenLoadFailure: Error {}

/// Only `budgetProgress` throws — this screen never calls the other
/// `InsightsStore` methods, so they can return empty rather than also throw.
@MainActor
private final class FailingBudgetProgressInsightsStore: InsightsStore {
  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw BudgetsScreenLoadFailure() }
  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { throw BudgetsScreenLoadFailure() }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}

#Preview("Budgets — failed to load, dark") {
  NavigationStack {
    BudgetsScreen(budgetStore: FakeBudgetStore(budgets: []), insightsStore: FailingBudgetProgressInsightsStore())
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: []))
  .preferredColorScheme(.dark)
}
