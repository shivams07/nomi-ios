import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Budgets page (U12; BS). Category-level only: no whole-app cap exists or
/// should be added (spec Assumptions). Shape from the approved `Budgets`
/// artboard: an H0 large title, one ring card (month, days left, the left-to-spend
/// figure inside the ring, the pace line as its caption), then a two-column grid
/// of category tiles. Each tile is one button into the editor and carries its
/// own 6 pt progress bar. The nav "+" appears only while a category has no budget.
public struct BudgetsScreen: View {
  public let budgetStore: BudgetStore
  public let insightsStore: InsightsStore

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query private var budgetRows: [NomiCore.Budget]
  @State private var editingCategory: NomiCore.Category?
  @State private var isAddingBudget = false
  @State private var now = Date()
  @State private var retryToken = 0

  public init(budgetStore: BudgetStore, insightsStore: InsightsStore) {
    self.budgetStore = budgetStore
    self.insightsStore = insightsStore
  }

  /// `nil` means the fetch threw. That is distinct from a legitimate
  /// zero-budgets month, which is `[]` and renders `emptyState`.
  private var progress: [BudgetProgress]? {
    _ = retryToken
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

  private var showsAddButton: Bool {
    BudgetsLogic.showsAddButton(unbudgetedCount: unbudgetedCategories.count)
  }

  private func amountMinor(for categoryID: UUID) -> Int {
    budgetRows.first { $0.categoryID == categoryID }?.amountMinor ?? 0
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.md) {
        if let progress {
          if progress.isEmpty {
            emptyState
          } else if let totals = BudgetTotals.compute(progress) {
            gaugeCard(totals: totals)
            categoryBudgetsSection(for: progress)
          }
        } else {
          NomiLoadFailedCard(message: "Budgets didn’t load.") {
            retryToken += 1
          }
        }
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.sm)
    }
    .background(NomiColor.ground)
    .navigationTitle("Budgets")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .toolbar {
      if showsAddButton {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isAddingBudget = true
          } label: {
            NomiNavIcon(systemName: "plus")
          }
          .accessibilityLabel("Add budget")
        }
      }
    }
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

  private var emptyState: some View {
    NomiEmptyState(
      systemImage: "chart.pie",
      title: "No budgets yet",
      message: "Set a monthly limit for a category and Nomi will track your spending against it here.",
      actionTitle: showsAddButton ? "Add budget" : nil
    ) {
      isAddingBudget = true
    }
    .padding(.top, 96)
  }

  private var elapsedFraction: Double {
    let calendar = Calendar.current
    guard let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count else { return 0 }
    let today = calendar.component(.day, from: now)
    return Double(today) / Double(daysInMonth)
  }

  private func gaugeCard(totals: BudgetTotals.Totals) -> some View {
    let daysLeft = BudgetDaysLeft.remaining(from: now)
    let pace = BudgetPace.assess(spentFraction: totals.fraction, elapsedFraction: elapsedFraction)
    let centreCaption = BudgetGaugeText.centreCaption(remainingMinor: totals.remainingMinor)
    let centreAmount = abs(totals.remainingMinor)
    return VStack(spacing: NomiSpacing.sm) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
          Text("Monthly")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
          Text(BudgetPeriodText.monthRange(for: now))
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: NomiSpacing.xxs) {
          Text("Days left")
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
          Text("\(daysLeft) days")
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
        }
      }
      ZStack {
        NomiRingGauge(fraction: totals.fraction, lineWidth: 14)
          .frame(width: 150, height: 150)
        VStack(spacing: NomiSpacing.xxs) {
          Text(centreCaption)
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
          SizedAmountText(minor: centreAmount, fontName: NomiFont.interRegular, size: 22)
          Text("\(BudgetGaugeText.percentUsed(fraction: totals.fraction))% used")
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
        }
        .frame(maxWidth: 124)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(BudgetGaugeText.spokenPercent(fraction: totals.fraction)), \(centreCaption) \(NomiFormatters.amountString(minor: centreAmount))"
      )
      Text(pace.line(overByMinor: -totals.remainingMinor))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.dayHeader)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
    .nomiCard(padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
  }

  private func categoryBudgetsSection(for progress: [BudgetProgress]) -> some View {
    let columns = [
      GridItem(.flexible(), spacing: NomiSpacing.cardGap),
      GridItem(.flexible(), spacing: NomiSpacing.cardGap),
    ]
    return VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
      Text("Category budgets")
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.ink)
        .accessibilityAddTraits(.isHeader)
      LazyVGrid(columns: columns, spacing: NomiSpacing.cardGap) {
        ForEach(progress) { item in
          budgetTile(for: item)
        }
      }
      if !showsAddButton {
        Text(BudgetsLogic.everyCategoryBudgetedCaption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity)
          .padding(.top, NomiSpacing.xs)
      }
    }
  }

  private func budgetTile(for item: BudgetProgress) -> some View {
    let remaining = item.budgetMinor - item.spentMinor
    let caption = BudgetTileCaption.text(remaining)
    return Button {
      if let category = categories.first(where: { $0.id == item.id }) {
        editingCategory = category
      }
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        NomiCategoryBadge(symbolName: item.symbolName, paletteSlot: item.paletteSlot, size: 40)
        Text(item.categoryName)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
          .padding(.top, 10)
        SizedAmountText(minor: item.spentMinor, fontName: NomiFont.interRegular, size: 20)
          .padding(.top, 4)
        tileCaption(caption)
          .padding(.top, 8)
        NomiProgressBar(fraction: item.fraction)
          .padding(.top, 8)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .nomiCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      BudgetTileSpeech.label(
        name: item.categoryName,
        spentMinor: item.spentMinor,
        remainingMinor: remaining,
        fraction: item.fraction
      )
    )
  }

  /// "₹600.00 over" carries a "!" glyph and the error red, so over-budget
  /// never rests on colour alone. Under budget the caption is plain.
  @ViewBuilder
  private func tileCaption(_ caption: (text: String, isOver: Bool)) -> some View {
    if caption.isOver {
      HStack(spacing: 4) {
        Text("!")
          .font(.custom(NomiFont.interSemiBold, size: 10, relativeTo: .caption2))
          .foregroundStyle(NomiColor.onPrimary)
          .frame(width: 14, height: 14)
          .background(Circle().fill(NomiColor.error))
          .accessibilityHidden(true)
        Text(caption.text)
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.error)
      }
    } else {
      Text(caption.text)
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
    }
  }
}

/// An amount drawn at an exact artboard size, with the decimals dimmed to the
/// ground's 65% ink (SIMP §1 rule 4). `NomiAmountText` takes only `NomiTextStyle`
/// roles, and the Budgets and Subscriptions artboards set 20, 22 and 32 Regular,
/// which no role names. The split still comes from `NomiAmountFormat`, so the
/// sign and grouping match every other amount. Shared with `SubscriptionsScreen`.
struct SizedAmountText: View {
  let minor: Int
  let fontName: String
  let size: CGFloat
  var tracking: CGFloat = 0

  var body: some View {
    let parts = NomiAmountFormat.parts(minor: minor)
    (Text(parts.sign + parts.integer)
      .font(.custom(fontName, size: size, relativeTo: .body))
      .foregroundStyle(NomiColor.ink)
      + Text(parts.decimals)
      .font(.custom(fontName, size: size, relativeTo: .body))
      .foregroundStyle(NomiColor.ink.opacity(NomiColor.decimalOpacityGround)))
      .tracking(tracking)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  }
}

/// The gauge card's date-range caption: "1 Sep – 30 Sep", the current
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

#Preview("Budgets — no budgets set") {
  NavigationStack {
    BudgetsScreen(budgetStore: FakeBudgetStore(budgets: []), insightsStore: BudgetsPreviewSupport.makeInsightsStore(progress: []))
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: []))
  .preferredColorScheme(.light)
}

#Preview("Budgets — mixed thresholds") {
  NavigationStack {
    BudgetsScreen(
      budgetStore: FakeBudgetStore(budgets: BudgetsPreviewSupport.sampleBudgets),
      insightsStore: BudgetsPreviewSupport.makeInsightsStore()
    )
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: BudgetsPreviewSupport.sampleBudgets))
  .preferredColorScheme(.light)
}

private struct BudgetsScreenLoadFailure: Error {}

/// Only `budgetProgress` throws. This screen never calls the other
/// `InsightsStore` methods, so they can return empty rather than also throw.
@MainActor
private final class FailingBudgetProgressInsightsStore: InsightsStore {
  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw BudgetsScreenLoadFailure() }
  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { throw BudgetsScreenLoadFailure() }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}

#Preview("Budgets — failed to load") {
  NavigationStack {
    BudgetsScreen(budgetStore: FakeBudgetStore(budgets: []), insightsStore: FailingBudgetProgressInsightsStore())
  }
  .modelContainer(BudgetsPreviewSupport.makeContainer(budgets: []))
  .preferredColorScheme(.light)
}
