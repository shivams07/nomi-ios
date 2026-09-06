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

    guard case .loaded(let rows) = DashboardWiring.recentTransactions(from: spy) else {
      return XCTFail("a non-throwing store must yield .loaded")
    }

    XCTAssertTrue(rows.isEmpty)
    XCTAssertEqual(spy.recentLimits, [5])
    XCTAssertEqual(DashboardWiring.recentTransactionLimit, 5)
    XCTAssertTrue(
      spy.transactionsInPeriodCallCount == 0,
      "transactions(in:) is the all-time fetch F2 removes; the dashboard must not call it")
  }

  /// F3: a store error must be distinguishable from a genuinely empty
  /// answer, not collapsed into the same empty card `try?` used to produce.
  @MainActor
  func testAThrowingStoreYieldsFailedNotLoadedEmpty() {
    let spy = SpyInsightsStore(shouldThrow: true)

    let result = DashboardWiring.recentTransactions(from: spy)

    guard case .failed = result else {
      return XCTFail("a throwing store must yield .failed, not .loaded([])")
    }
    XCTAssertEqual(spy.recentLimits, [5], "the call must still have been made")
  }

  // MARK: - F5: FY basis has no budget month

  private var ist: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return ist.date(from: components)!
  }

  func testBudgetMonthIsNilForFinancialYearBasis() {
    XCTAssertNil(DashboardWiring.budgetMonth(basis: .financialYear, anchor: date(2026, 9), calendar: ist))
  }

  func testBudgetMonthIsYearAndMonthForCalendarMonthBasis() {
    let month = DashboardWiring.budgetMonth(basis: .calendarMonth, anchor: date(2026, 9), calendar: ist)
    XCTAssertEqual(month?.year, 2026)
    XCTAssertEqual(month?.month, 9)
  }

  // MARK: - F3: the rest of the dashboard's reads

  @MainActor
  func testAThrowingInsightsStoreYieldsFailedNotLoadedEmpty() {
    let spy = SpyInsightsStore(shouldThrow: true)

    guard case .failed = DashboardWiring.insights(for: .month(year: 2026, month: 9), from: spy) else {
      return XCTFail("a throwing store must yield .failed, not .loaded(empty)")
    }
  }

  @MainActor
  func testANonThrowingInsightsStoreYieldsLoaded() {
    let spy = SpyInsightsStore()

    guard case .loaded = DashboardWiring.insights(for: .month(year: 2026, month: 9), from: spy) else {
      return XCTFail("a non-throwing store must yield .loaded")
    }
  }

  @MainActor
  func testAThrowingAccountsStoreYieldsFailed() {
    let spy = SpyInsightsStore(shouldThrow: true)

    guard case .failed = DashboardWiring.accounts(from: spy) else {
      return XCTFail("a throwing store must yield .failed")
    }
  }

  @MainActor
  func testBudgetProgressIsNilWhenMonthIsNil() {
    let spy = SpyInsightsStore()
    XCTAssertNil(DashboardWiring.budgetProgress(month: nil, from: spy))
  }

  @MainActor
  func testAThrowingBudgetProgressStoreYieldsFailedWhenAMonthExists() {
    let spy = SpyInsightsStore(shouldThrow: true)

    guard case .failed = DashboardWiring.budgetProgress(month: (2026, 9), from: spy) else {
      return XCTFail("a throwing store must yield .failed when there is a month to evaluate")
    }
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

  func insights(for period: InsightPeriod) throws -> PeriodInsights {
    if shouldThrow { throw Failure() }
    return PeriodInsights(
      period: period, debitMinor: 0, creditMinor: 0, netMinor: 0,
      priorDebitMinor: nil, priorCreditMinor: nil, transactionCount: 0, byDay: [], byCategory: [],
      topMerchants: [], needsReviewCount: 0, uncategorizedCount: 0
    )
  }

  func trend(months: Int) throws -> [MonthBucket] { [] }

  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] {
    if shouldThrow { throw Failure() }
    return []
  }

  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    if shouldThrow { throw Failure() }
    return []
  }
}
