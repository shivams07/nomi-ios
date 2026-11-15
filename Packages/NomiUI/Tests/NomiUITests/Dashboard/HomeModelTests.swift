import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S1a. `HomeModel`'s reads: one read per store call per load, a failed read
/// that leaves the other modules loaded, the fiscal-year basis with no budget
/// read, and a switch of the hero's kind that reads nothing.
@MainActor
final class HomeModelTests: XCTestCase {
  func testNothingIsLoadedBeforeTheFirstLoad() {
    let model = HomeModel(insightsStore: CountingInsightsStore(), recurringStore: CountingRecurringStore())
    XCTAssertNil(model.insights)
    XCTAssertNil(model.recentTransactions)
    XCTAssertNil(model.needsReview)
    XCTAssertNil(model.budgets)
    XCTAssertNil(model.upcoming)
  }

  /// One read per store call per load key: the period, the refresh token and
  /// the retry token together are one key, and one key is one load.
  func testLoadReadsEachStoreOnceForTheCalendarMonth() {
    let store = CountingInsightsStore()
    let recurring = CountingRecurringStore()
    let model = HomeModel(insightsStore: store, recurringStore: recurring)
    model.load(period: .month(year: 2026, month: 11))
    XCTAssertEqual(store.insightsCalls, 1)
    XCTAssertEqual(store.recentCalls, 1)
    XCTAssertEqual(store.reviewCalls, 1)
    XCTAssertEqual(store.budgetCalls, 1)
    XCTAssertEqual(recurring.calls, 1)
  }

  func testEachLoadReadsAgainBecauseEachLoadIsANewKey() {
    let store = CountingInsightsStore()
    let model = HomeModel(insightsStore: store, recurringStore: nil)
    model.load(period: .month(year: 2026, month: 11))
    model.load(period: .month(year: 2026, month: 11))
    XCTAssertEqual(store.insightsCalls, 2)
    XCTAssertEqual(store.recentCalls, 2)
  }

  /// Switching the hero's kind is a view-state change. It reads nothing.
  func testSwitchingKindReadsNothingNew() {
    let store = CountingInsightsStore()
    let recurring = CountingRecurringStore()
    let model = HomeModel(insightsStore: store, recurringStore: recurring)
    model.load(period: .month(year: 2026, month: 11))
    model.kind = .income
    model.kind = .spent
    XCTAssertEqual(store.insightsCalls, 1)
    XCTAssertEqual(store.recentCalls, 1)
    XCTAssertEqual(store.reviewCalls, 1)
    XCTAssertEqual(store.budgetCalls, 1)
    XCTAssertEqual(recurring.calls, 1)
  }

  func testTheHeroKindDefaultsToSpent() {
    let model = HomeModel(insightsStore: CountingInsightsStore(), recurringStore: nil)
    XCTAssertEqual(model.kind, .spent)
  }

  /// A failed insights read is the hero's failed state. The other modules
  /// still load, each as its own read.
  func testFailedInsightsLeavesTheOtherModulesLoaded() {
    let store = CountingInsightsStore()
    store.failInsights = true
    let model = HomeModel(insightsStore: store, recurringStore: CountingRecurringStore())
    model.load(period: .month(year: 2026, month: 11))
    guard case .failed? = model.insights else {
      return XCTFail("a failed insights read must be .failed, not loaded")
    }
    guard case .loaded? = model.recentTransactions else {
      return XCTFail("recent transactions must still load")
    }
    guard case .loaded? = model.needsReview else {
      return XCTFail("the review count must still load")
    }
    guard case .monthly(.loaded)? = model.budgets else {
      return XCTFail("budgets must still load")
    }
  }

  /// A failed all-time review read is a failure, never a zero.
  func testAFailedReviewReadIsFailedNotZero() {
    let store = CountingInsightsStore()
    store.failReview = true
    let model = HomeModel(insightsStore: store, recurringStore: nil)
    model.load(period: .month(year: 2026, month: 11))
    guard case .failed? = model.needsReview else {
      return XCTFail("a failed review read must be .failed, not .loaded(0)")
    }
  }

  /// The financial year has no monthly budget, so there is no budget read.
  func testFinancialYearLoadMakesNoBudgetRead() {
    let store = CountingInsightsStore()
    let model = HomeModel(insightsStore: store, recurringStore: nil)
    model.load(period: .financialYear(startingYear: 2026))
    XCTAssertEqual(store.budgetCalls, 0)
    guard case .notMonthly? = model.budgets else {
      return XCTFail("the fiscal-year basis has no budget module, not a loading one")
    }
  }

  /// No recurring store means no Upcoming card: absent, and nothing read.
  func testWithoutARecurringStoreUpcomingIsAbsent() {
    let model = HomeModel(insightsStore: CountingInsightsStore(), recurringStore: nil)
    model.load(period: .month(year: 2026, month: 11))
    guard case .absent? = model.upcoming else {
      return XCTFail("no recurring store must be .absent")
    }
  }

  func testAThrowingRecurringStoreYieldsFailed() {
    let recurring = CountingRecurringStore()
    recurring.shouldThrow = true
    let model = HomeModel(insightsStore: CountingInsightsStore(), recurringStore: recurring)
    model.load(period: .month(year: 2026, month: 11))
    guard case .loaded(.failed)? = model.upcoming else {
      return XCTFail("a failed recurring read must be .loaded(.failed)")
    }
  }
}

/// A store that counts each read. The protocol's requirements, built the same
/// way `DashboardWiringTests` builds its spy, so this compiles against the same
/// protocol surface.
@MainActor
private final class CountingInsightsStore: InsightsStore {
  private(set) var insightsCalls = 0
  private(set) var recentCalls = 0
  private(set) var reviewCalls = 0
  private(set) var budgetCalls = 0
  var failInsights = false
  var failReview = false

  private struct Failure: Error {}

  func insights(for period: InsightPeriod) throws -> PeriodInsights {
    insightsCalls += 1
    if failInsights { throw Failure() }
    return PeriodInsights(
      period: period, debitMinor: 0, creditMinor: 0, netMinor: 0,
      priorDebitMinor: nil, priorCreditMinor: nil, transactionCount: 0, byDay: [], byCategory: [],
      topMerchants: [], needsReviewCount: 0, uncategorizedCount: 0
    )
  }

  func trend(months: Int) throws -> [MonthBucket] { [] }

  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }

  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    budgetCalls += 1
    return []
  }

  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }

  func recentTransactions(limit: Int) throws -> [NomiCore.Transaction] {
    recentCalls += 1
    return []
  }

  func needsReviewCountAllTime() throws -> Int {
    reviewCalls += 1
    if failReview { throw Failure() }
    return 0
  }
}

@MainActor
private final class CountingRecurringStore: RecurringInsightsStore {
  private(set) var calls = 0
  var shouldThrow = false

  private struct Failure: Error {}

  func recurringSeries() throws -> [RecurringSeries] {
    calls += 1
    if shouldThrow { throw Failure() }
    return []
  }
}
