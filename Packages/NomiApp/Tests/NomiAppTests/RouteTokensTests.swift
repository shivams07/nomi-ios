import XCTest

@testable import NomiApp

/// G1 and G4 (WR-3b). Every cache-backed root route takes its refresh token from
/// `RouteTokens`, built from one cache generation. A route that takes a literal
/// instead never re-reads after a sync or a Siri write, so each route has its
/// own test, and the Accounts route, which the R2 mutant named, has its own.
final class RouteTokensTests: XCTestCase {

  func testAccountsRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).accounts, 7)
  }

  func testBudgetsRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).budgets, 7)
  }

  func testSubscriptionsRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).subscriptions, 7)
  }

  func testSettingsRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).settings, 7)
  }

  func testReportsRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).reports, 7)
  }

  func testDashboardRouteCarriesTheGeneration() {
    XCTAssertEqual(RouteTokens(generation: 7).dashboard, 7)
  }

  /// A new generation must reach every route, not only the first value. The
  /// two values differ on every route, so a route stuck on one of them fails.
  func testANewGenerationChangesEveryRouteToken() {
    let before = RouteTokens(generation: 7)
    let after = RouteTokens(generation: 8)

    XCTAssertNotEqual(before.dashboard, after.dashboard)
    XCTAssertNotEqual(before.budgets, after.budgets)
    XCTAssertNotEqual(before.subscriptions, after.subscriptions)
    XCTAssertNotEqual(before.settings, after.settings)
    XCTAssertNotEqual(before.reports, after.reports)
    XCTAssertNotEqual(before.accounts, after.accounts)
    XCTAssertEqual(after.accounts, 8)
  }
}
