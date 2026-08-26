import NomiCore
import NomiPreview
import SwiftUI

/// Small, testable wiring rules that would otherwise be buried inside
/// `DashboardView.body` where XCTest cannot reach them. Kept together so the
/// AC-mandated behaviour (archived exclusion, budget-module absence) reads as
/// a policy, not an accident of how the view happens to be written.
enum DashboardWiring {
  /// The accounts card never sees archived accounts — done-when: "Archived
  /// accounts are excluded from the accounts card."
  static let accountsIncludeArchived = false

  /// Done-when: "a preview with zero budgets renders NO budget module at
  /// all... an absent view and not a hidden one." `DashboardView` acts on
  /// this with `if DashboardWiring.shouldShowBudgetModule(...)`, never
  /// `.hidden()` or `.opacity(0)`, so a `false` here means the module is
  /// never constructed.
  static func shouldShowBudgetModule(_ items: [BudgetProgress]) -> Bool {
    !items.isEmpty
  }
}

/// The home screen (U9). Composes the period selector and every dashboard
/// card, reading exclusively through `InsightsStore` and
/// `MailConnectionService` — never `NomiIngest`, which `NomiUI` cannot import
/// at all (enforced by the package graph, not by discipline).
public struct DashboardView: View {
  public let insightsStore: InsightsStore
  public let mailConnectionService: MailConnectionService?

  @State private var basis: PeriodBasis = .calendarMonth
  @State private var anchor: Date = Date()
  @State private var mailState: MailConnectionState = .disconnected

  public init(insightsStore: InsightsStore, mailConnectionService: MailConnectionService? = nil) {
    self.insightsStore = insightsStore
    self.mailConnectionService = mailConnectionService
  }

  private var period: InsightPeriod {
    DashboardPeriod.period(basis: basis, anchor: anchor)
  }

  private var insights: PeriodInsights? {
    try? insightsStore.insights(for: period)
  }

  private var accounts: [AccountSummary] {
    (try? insightsStore.accountSummaries(includeArchived: DashboardWiring.accountsIncludeArchived)) ?? []
  }

  private var budgetProgress: [BudgetProgress] {
    let components = Calendar.current.dateComponents([.year, .month], from: anchor)
    guard let year = components.year, let month = components.month else { return [] }
    return (try? insightsStore.budgetProgress(year: year, month: month)) ?? []
  }

  private var recentTransactions: [NomiCore.Transaction] {
    (try? insightsStore.transactions(in: .allTime)) ?? []
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NomiSpacing.cardToCard) {
        SyncStatusRow(state: mailState)
        periodSelector
        if let insights {
          HeroTotalCard(insights: insights)
          SpendPerDayChartCard(byDay: insights.byDay)
          CategoryBreakdownCard(slices: insights.byCategory)
          if DashboardWiring.shouldShowBudgetModule(budgetProgress) {
            BudgetProgressCard(items: budgetProgress)
          }
          RecentTransactionsCard(transactions: recentTransactions)
          TopMerchantsCard(merchants: insights.topMerchants)
          NeedsYouCard(needsReviewCount: insights.needsReviewCount, uncategorizedCount: insights.uncategorizedCount)
        }
        AccountsCard(accounts: accounts)
      }
      .padding(.horizontal, NomiSpacing.screenGutter)
      .padding(.vertical, NomiSpacing.screenGutter)
    }
    .task {
      guard let mailConnectionService else { return }
      for await state in mailConnectionService.state {
        mailState = state
      }
    }
  }

  private var periodSelector: some View {
    HStack(spacing: NomiSpacing.sm) {
      Button {
        anchor = DashboardPeriod.shiftedAnchor(anchor, basis: basis, by: -1)
      } label: {
        Image(systemName: "chevron.left")
          .foregroundStyle(NomiColor.textSecondary)
      }
      Text(DashboardPeriod.label(for: period))
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        anchor = DashboardPeriod.shiftedAnchor(anchor, basis: basis, by: 1)
      } label: {
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.textSecondary)
      }
      NomiSegmentedPill(basis: $basis)
    }
  }
}

#Preview("Dashboard — default, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — accessibility 3, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(), mailConnectionService: FakeMailConnectionService())
  }
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — thin state, under 10 transactions, dark") {
  NomiTabShell {
    DashboardView(
      insightsStore: FakeInsightsStore(transactions: Array(PreviewData.transactions.prefix(6)), budgets: []),
      mailConnectionService: FakeMailConnectionService()
    )
  }
  .preferredColorScheme(.dark)
}

#Preview("Dashboard — zero budgets, module absent, dark") {
  NomiTabShell {
    DashboardView(insightsStore: FakeInsightsStore(budgets: []), mailConnectionService: FakeMailConnectionService())
  }
  .preferredColorScheme(.dark)
}
