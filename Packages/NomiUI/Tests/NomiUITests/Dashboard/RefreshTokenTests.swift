import NomiCore
import XCTest

@testable import NomiUI

/// A store that never has to be configured because these tests never let a
/// view read from it — only construct it, so identity is all that matters.
private final class NoopInsightsStore: InsightsStore {
  func insights(for period: InsightPeriod) throws -> PeriodInsights {
    throw CancellationError()
  }

  func trend(months: Int) throws -> [MonthBucket] { [] }

  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }

  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }

  func transactions(in period: InsightPeriod) throws -> [Transaction] { [] }
}

/// G4 stubs for the three screens that take a store they never let a test
/// read from. Identity is all these tests need.
@MainActor
private final class NoopRecurringStore: RecurringInsightsStore {
  func recurringSeries() throws -> [RecurringSeries] { [] }
}

@MainActor
private final class NoopBudgetStore: BudgetStore {
  func setBudget(categoryID: UUID, amountMinor: Int) throws {}
  func removeBudget(categoryID: UUID) throws {}
  func budgets() throws -> [Budget] { [] }
}

@MainActor
private final class NoopAccountStore: AccountStore {
  func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String
  ) throws -> Account {
    throw CancellationError()
  }

  func rename(_ id: UUID, to displayName: String) throws {}
  func setArchived(_ id: UUID, _ archived: Bool) throws {}

  func update(
    _ id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws {}

  func delete(_ id: UUID) throws {}
}

final class RefreshTokenTests: XCTestCase {

  @MainActor
  func testDashboardViewValuesDifferingOnlyInRefreshTokenAreNotEqual() {
    let store = NoopInsightsStore()
    let lhs = DashboardView(insightsStore: store, refreshToken: 0)
    let rhs = DashboardView(insightsStore: store, refreshToken: 1)
    XCTAssertNotEqual(lhs, rhs)
  }

  @MainActor
  func testDashboardViewValuesWithSameRefreshTokenAreEqual() {
    let store = NoopInsightsStore()
    let lhs = DashboardView(insightsStore: store, refreshToken: 3)
    let rhs = DashboardView(insightsStore: store, refreshToken: 3)
    XCTAssertEqual(lhs, rhs)
  }

  @MainActor
  func testReportsScreenValuesDifferingOnlyInRefreshTokenAreNotEqual() {
    let store = NoopInsightsStore()
    let lhs = ReportsScreen(insightsStore: store, refreshToken: 0)
    let rhs = ReportsScreen(insightsStore: store, refreshToken: 1)
    XCTAssertNotEqual(lhs, rhs)
  }

  @MainActor
  func testReportsScreenValuesWithSameRefreshTokenAreEqual() {
    let store = NoopInsightsStore()
    let lhs = ReportsScreen(insightsStore: store, refreshToken: 5)
    let rhs = ReportsScreen(insightsStore: store, refreshToken: 5)
    XCTAssertEqual(lhs, rhs)
  }

  // MARK: - G4: the cache-backed screens compare the generation

  @MainActor
  func testAccountsScreenValuesDifferingOnlyInRefreshTokenAreNotEqual() {
    let accounts = NoopAccountStore()
    let insights = NoopInsightsStore()
    let lhs = AccountsScreen(accountStore: accounts, insightsStore: insights, refreshToken: 0)
    let rhs = AccountsScreen(accountStore: accounts, insightsStore: insights, refreshToken: 1)
    XCTAssertNotEqual(lhs, rhs)
  }

  @MainActor
  func testAccountsScreenValuesWithSameRefreshTokenAreEqual() {
    let accounts = NoopAccountStore()
    let insights = NoopInsightsStore()
    let lhs = AccountsScreen(accountStore: accounts, insightsStore: insights, refreshToken: 4)
    let rhs = AccountsScreen(accountStore: accounts, insightsStore: insights, refreshToken: 4)
    XCTAssertEqual(lhs, rhs)
  }

  @MainActor
  func testBudgetsScreenValuesDifferingOnlyInRefreshTokenAreNotEqual() {
    let budgets = NoopBudgetStore()
    let insights = NoopInsightsStore()
    let lhs = BudgetsScreen(budgetStore: budgets, insightsStore: insights, refreshToken: 0)
    let rhs = BudgetsScreen(budgetStore: budgets, insightsStore: insights, refreshToken: 1)
    XCTAssertNotEqual(lhs, rhs)
  }

  @MainActor
  func testBudgetsScreenValuesWithSameRefreshTokenAreEqual() {
    let budgets = NoopBudgetStore()
    let insights = NoopInsightsStore()
    let lhs = BudgetsScreen(budgetStore: budgets, insightsStore: insights, refreshToken: 6)
    let rhs = BudgetsScreen(budgetStore: budgets, insightsStore: insights, refreshToken: 6)
    XCTAssertEqual(lhs, rhs)
  }

  @MainActor
  func testSubscriptionsScreenValuesDifferingOnlyInRefreshTokenAreNotEqual() {
    let store = NoopRecurringStore()
    let lhs = SubscriptionsScreen(recurringStore: store, refreshToken: 0)
    let rhs = SubscriptionsScreen(recurringStore: store, refreshToken: 1)
    XCTAssertNotEqual(lhs, rhs)
  }

  @MainActor
  func testSubscriptionsScreenValuesWithSameRefreshTokenAreEqual() {
    let store = NoopRecurringStore()
    let lhs = SubscriptionsScreen(recurringStore: store, refreshToken: 2)
    let rhs = SubscriptionsScreen(recurringStore: store, refreshToken: 2)
    XCTAssertEqual(lhs, rhs)
  }
}
