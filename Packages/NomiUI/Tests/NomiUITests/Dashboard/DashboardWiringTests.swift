import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class DashboardWiringTests: XCTestCase {
  func testAccountsCardRequestsArchivedAccountsExcluded() {
    XCTAssertFalse(DashboardWiring.accountsIncludeArchived)
  }

  func testBudgetModuleIsHiddenWhenNoBudgetsExist() {
    XCTAssertFalse(DashboardWiring.shouldShowBudgetModule([]))
  }

  func testBudgetModuleShowsWhenAtLeastOneBudgetExists() {
    let item = BudgetProgress(
      id: UUID(),
      categoryName: "Food & Dining",
      paletteSlot: 0,
      budgetMinor: 5000_00,
      spentMinor: 1000_00,
      fraction: 0.2,
      periodKey: "2026-08"
    )
    XCTAssertTrue(DashboardWiring.shouldShowBudgetModule([item]))
  }

  func testBudgetLineFormatsSpentOfBudget() {
    let item = BudgetProgress(
      id: UUID(),
      categoryName: "Food & Dining",
      paletteSlot: 0,
      budgetMinor: 5000_00,
      spentMinor: 1000_00,
      fraction: 0.2,
      periodKey: "2026-08"
    )
    let line = BudgetProgressCard.line(for: item)
    XCTAssertTrue(line.contains("of"))
    XCTAssertTrue(line.contains("₹"))
  }

  // MARK: - F2: the recent card does not read the whole ledger

  @MainActor
  func testRecentTransactionsAsksForFiveAndNeverForAllTime() {
    let spy = SpyInsightsStore()

    _ = DashboardWiring.recentTransactions(from: spy)

    XCTAssertEqual(spy.recentLimits, [5])
    XCTAssertEqual(DashboardWiring.recentTransactionLimit, 5)
    XCTAssertTrue(
      spy.transactionsInPeriodCallCount == 0,
      "transactions(in:) is the all-time fetch F2 removes; the dashboard must not call it")
  }

  /// The call is wrapped in `try?`, so a store error has to become an empty
  /// card rather than a crash - and the call must still have been made.
  @MainActor
  func testAThrowingStoreProducesAnEmptyCardNotACrash() {
    let spy = SpyInsightsStore(shouldThrow: true)

    let rows = DashboardWiring.recentTransactions(from: spy)

    XCTAssertTrue(rows.isEmpty)
    XCTAssertEqual(spy.recentLimits, [5])
  }
}

/// Records which read the dashboard actually issues.
///
/// `DashboardView.body` is not reachable from `swift test`, which is why the
/// call lives in `DashboardWiring` and this holds that function rather than the
/// view. It returns no rows on purpose: what is being asserted is which method
/// was called, and this package's tests deliberately avoid constructing a
/// `Transaction` (`RecentTransactionsSortTests` next door says why).
@MainActor
private final class SpyInsightsStore: InsightsStore {
  private(set) var recentLimits: [Int] = []
  private(set) var transactionsInPeriodCallCount = 0
  private let shouldThrow: Bool

  init(shouldThrow: Bool = false) {
    self.shouldThrow = shouldThrow
  }

  private struct Failure: Error {}

  func recentTransactions(limit: Int) throws -> [NomiCore.Transaction] {
    recentLimits.append(limit)
    if shouldThrow { throw Failure() }
    return []
  }

  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] {
    transactionsInPeriodCallCount += 1
    return []
  }

  func insights(for period: InsightPeriod) throws -> PeriodInsights { throw Failure() }
  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
}
