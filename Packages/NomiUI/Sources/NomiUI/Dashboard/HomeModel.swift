import Foundation
import NomiCore
import Observation

/// The Home screen's reads, outside the view (S1a). `DashboardView` loads it from
/// `.task(id:)`, and its body reads only these properties, so no store is read
/// on a render. Each module is its own read, so a failure is that module's
/// failure and nothing else's. `nil` means not loaded yet.
@Observable @MainActor final class HomeModel {
  /// The hero's comparison. Switching it is view state: it reads nothing.
  var kind: NomiComparisonCopy.Kind = .spent

  /// The budget module's read. A financial year is not a calendar month, so it
  /// has no monthly budget and no read at all. That is a state of its own, not a failure.
  enum BudgetRead {
    case monthly(DashboardWiring.Load<[BudgetProgress]>)
    case notMonthly
  }

  /// The Upcoming card's read. `absent` is a model with no recurring store:
  /// the card is not built, and nothing is read.
  enum UpcomingRead {
    case absent
    case loaded(DashboardWiring.Load<[RecurringSeries]>)
  }

  /// The Review card's read (S1b). `absent` is a model with no transaction store:
  /// the card is not built, and nothing is read.
  enum ReviewRead {
    case absent
    case loaded(DashboardWiring.Load<ReviewCounts>)
  }

  @ObservationIgnored private let insightsStore: InsightsStore
  @ObservationIgnored private let recurringStore: RecurringInsightsStore?
  @ObservationIgnored private let transactionStore: TransactionStore?

  private(set) var insights: DashboardWiring.Load<PeriodInsights>?
  private(set) var recentTransactions: DashboardWiring.Load<[NomiCore.Transaction]>?
  private(set) var needsReview: DashboardWiring.Load<Int>?
  private(set) var budgets: BudgetRead?
  private(set) var upcoming: UpcomingRead?
  private(set) var review: ReviewRead?
  /// Account names by id, for the Recent rows. Archived accounts are included, so
  /// a row from one still reads its name.
  private(set) var accountNames: DashboardWiring.Load<[UUID: String]>?

  init(
    insightsStore: InsightsStore,
    recurringStore: RecurringInsightsStore?,
    transactionStore: TransactionStore? = nil
  ) {
    self.insightsStore = insightsStore
    self.recurringStore = recurringStore
    self.transactionStore = transactionStore
  }

  /// One read per store call. Called once per load key (period, refresh token,
  /// retry token) from `DashboardView`'s `.task(id:)`.
  func load(period: InsightPeriod) {
    insights = DashboardWiring.insights(for: period, from: insightsStore)
    recentTransactions = DashboardWiring.recentTransactions(from: insightsStore)
    needsReview = DashboardWiring.needsReviewAllTime(from: insightsStore)
    budgets = budgetRead(for: period)
    upcoming = recurringStore.map { UpcomingRead.loaded(DashboardWiring.recurringSeries(from: $0)) } ?? .absent
    review = transactionStore.map { ReviewRead.loaded(DashboardWiring.reviewCount(from: $0, insightsStore: insightsStore, now: Date())) } ?? .absent
    accountNames = DashboardWiring.accountNames(from: insightsStore)
  }

  /// Monthly budgets are read for a calendar month only.
  private func budgetRead(for period: InsightPeriod) -> BudgetRead {
    let month: (year: Int, month: Int)?
    switch period {
    case .month(let calendarYear, let calendarMonth):
      month = (year: calendarYear, month: calendarMonth)
    case .financialYear, .trailingMonths, .allTime:
      month = nil
    }
    guard let load = DashboardWiring.budgetProgress(month: month, from: insightsStore) else {
      return .notMonthly
    }
    return .monthly(load)
  }
}
