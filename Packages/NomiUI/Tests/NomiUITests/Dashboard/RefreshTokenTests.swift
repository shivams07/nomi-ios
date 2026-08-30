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
}
