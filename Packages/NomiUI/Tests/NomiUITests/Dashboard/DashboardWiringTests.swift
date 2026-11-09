import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class DashboardWiringTests: XCTestCase {
  func testAccountsCardRequestsArchivedAccountsExcluded() {
    XCTAssertFalse(DashboardWiring.accountsIncludeArchived)
  }

  func testBudgetModuleIsPromptWhenNoBudgetsExist() {
    XCTAssertEqual(DashboardWiring.budgetModule([]), .prompt)
  }

  func testBudgetModuleIsRemainingWithTotalsWhenBudgetsExist() {
    let item = BudgetProgress(
      id: UUID(),
      categoryName: "Food & Dining",
      paletteSlot: 0,
      budgetMinor: 5000_00,
      spentMinor: 1000_00,
      fraction: 0.2,
      periodKey: "2026-08"
    )
    guard case .remaining(let totals) = DashboardWiring.budgetModule([item]) else {
      return XCTFail("a non-empty list must yield .remaining")
    }
    XCTAssertEqual(totals, BudgetTotals.compute([item]))
  }

  func testRecentBadgesLookupKeepsFirstOfDuplicateIDs() {
    let id = UUID()
    let first = CategoryBadge(id: id, name: "Food", symbolName: "fork.knife", paletteSlot: 0)
    let second = CategoryBadge(id: id, name: "Food Dup", symbolName: "cart", paletteSlot: 1)
    let lookup = RecentBadges.lookup([first, second])
    XCTAssertEqual(lookup[id]?.name, "Food")
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

  // MARK: - D26: the Needs-you review count is the all-time one

  /// Built without a `Transaction` (see `SpyInsightsStore`).
  private func period(needsReview: Int, uncategorized: Int) -> PeriodInsights {
    PeriodInsights(
      period: .month(year: 2026, month: 9), debitMinor: 0, creditMinor: 0, netMinor: 0,
      priorDebitMinor: nil, priorCreditMinor: nil, transactionCount: 0, byDay: [], byCategory: [],
      topMerchants: [], needsReviewCount: needsReview, uncategorizedCount: uncategorized
    )
  }

  @MainActor
  func testNeedsReviewAllTimeReadsTheStoresAllTimeCount() {
    let spy = SpyInsightsStore()
    spy.needsReviewAllTimeValue = 7

    guard case .loaded(let count) = DashboardWiring.needsReviewAllTime(from: spy) else {
      return XCTFail("a non-throwing store must yield .loaded")
    }
    XCTAssertEqual(count, 7)
    XCTAssertEqual(spy.needsReviewAllTimeCallCount, 1)
  }

  /// A failed read is a failure, not a zero that hides the card's count.
  @MainActor
  func testAThrowingAllTimeReviewReadYieldsFailedNotZero() {
    let spy = SpyInsightsStore(shouldThrow: true)

    guard case .failed = DashboardWiring.needsReviewAllTime(from: spy) else {
      return XCTFail("a throwing store must yield .failed, not .loaded(0)")
    }
  }

  /// The card's review count is the all-time one. The period holds 5 and all time
  /// holds 7: the card must say 7.
  func testNeedsYouCountsTheAllTimeReviewNotThePeriodOne() {
    let inputs = DashboardWiring.needsYouInputs(
      period: period(needsReview: 5, uncategorized: 2),
      needsReviewAllTime: 7
    )
    XCTAssertEqual(inputs.needsReviewCount, 7)
  }

  /// The mirror image: a month with flagged rows and none all time cannot show
  /// a review count from the month.
  func testNeedsYouShowsNoReviewWhenAllTimeHasNone() {
    let inputs = DashboardWiring.needsYouInputs(
      period: period(needsReview: 3, uncategorized: 0),
      needsReviewAllTime: 0
    )
    XCTAssertEqual(inputs.needsReviewCount, 0)
  }

  /// The uncategorized count is still the selected period's.
  func testNeedsYouKeepsTheUncategorizedCountFromThePeriod() {
    let inputs = DashboardWiring.needsYouInputs(
      period: period(needsReview: 5, uncategorized: 4),
      needsReviewAllTime: 7
    )
    XCTAssertEqual(inputs.uncategorizedCount, 4)
  }

  /// With the all-time review count at zero, a card whose only count is
  /// uncategorized routes to the Uncategorized chip, not the review queue.
  func testAllTimeZeroReviewRoutesToUncategorized() {
    let inputs = DashboardWiring.needsYouInputs(
      period: period(needsReview: 9, uncategorized: 2),
      needsReviewAllTime: 0
    )
    XCTAssertEqual(
      DashboardWiring.needsYouDestination(
        needsReviewCount: inputs.needsReviewCount,
        uncategorizedCount: inputs.uncategorizedCount),
      .uncategorized)
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

  // MARK: - M9: NeedsYouCard tappability

  func testNeedsYouIsNotTappableWhenBothCountsAreZero() {
    XCTAssertFalse(DashboardWiring.needsYouIsTappable(needsReviewCount: 0, uncategorizedCount: 0))
  }

  func testNeedsYouIsTappableWhenNeedsReviewCountIsPositive() {
    XCTAssertTrue(DashboardWiring.needsYouIsTappable(needsReviewCount: 1, uncategorizedCount: 0))
  }

  func testNeedsYouIsTappableWhenUncategorizedCountIsPositive() {
    XCTAssertTrue(DashboardWiring.needsYouIsTappable(needsReviewCount: 0, uncategorizedCount: 1))
  }

  func testNeedsYouIsTappableWhenBothCountsArePositive() {
    XCTAssertTrue(DashboardWiring.needsYouIsTappable(needsReviewCount: 3, uncategorizedCount: 2))
  }

  // MARK: - G1: the Needs-you tap opens the chip its own count names

  func testNeedsYouDestinationIsReviewQueueWhenOnlyReviewCountIsPositive() {
    XCTAssertEqual(
      DashboardWiring.needsYouDestination(needsReviewCount: 2, uncategorizedCount: 0),
      .reviewQueue
    )
  }

  func testNeedsYouDestinationIsReviewQueueWhenBothCountsArePositive() {
    XCTAssertEqual(
      DashboardWiring.needsYouDestination(needsReviewCount: 2, uncategorizedCount: 3),
      .reviewQueue
    )
  }

  func testNeedsYouDestinationIsUncategorizedWhenOnlyUncategorizedCountIsPositive() {
    XCTAssertEqual(
      DashboardWiring.needsYouDestination(needsReviewCount: 0, uncategorizedCount: 3),
      .uncategorized
    )
  }

  func testNeedsYouDestinationIsNilWhenBothCountsAreZero() {
    XCTAssertNil(DashboardWiring.needsYouDestination(needsReviewCount: 0, uncategorizedCount: 0))
  }

  func testNeedsYouHandlerRunsReviewQueueWhenReviewCountIsPositive() {
    let handler = DashboardWiring.needsYouHandler(
      needsReviewCount: 2, uncategorizedCount: 3, reviewQueue: "review", uncategorized: "uncategorized"
    )
    XCTAssertEqual(handler, "review")
  }

  func testNeedsYouHandlerRunsUncategorizedWhenOnlyUncategorizedCountIsPositive() {
    let handler = DashboardWiring.needsYouHandler(
      needsReviewCount: 0, uncategorizedCount: 3, reviewQueue: "review", uncategorized: "uncategorized"
    )
    XCTAssertEqual(handler, "uncategorized")
  }

  func testNeedsYouHandlerIsNilWhenBothCountsAreZero() {
    let handler = DashboardWiring.needsYouHandler(
      needsReviewCount: 0, uncategorizedCount: 0, reviewQueue: "review", uncategorized: "uncategorized"
    )
    XCTAssertNil(handler)
  }

  func testNeedsYouHandlerIsNilWhenTheMatchingHandlerIsNotWired() {
    let handler: String? = DashboardWiring.needsYouHandler(
      needsReviewCount: 0, uncategorizedCount: 3, reviewQueue: "review", uncategorized: nil
    )
    XCTAssertNil(handler, "an uncategorized-only card must not fall back to the review queue")
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

  /// D26. Answered explicitly, not by the protocol default, so a test can set
  /// the all-time count and see which read the view's rule took it from.
  var needsReviewAllTimeValue = 0
  private(set) var needsReviewAllTimeCallCount = 0

  func needsReviewCountAllTime() throws -> Int {
    needsReviewAllTimeCallCount += 1
    if shouldThrow { throw Failure() }
    return needsReviewAllTimeValue
  }
}
