import NomiCore
import NomiPreview
import XCTest

@testable import NomiUI

/// G4. `RootView` passes `environment.insightsGeneration` to `SettingsScreen`,
/// and `SettingsScreen` passes it on to the Budgets row it draws. These tests
/// pin the second hop: what reaches `BudgetsScreen`'s initialiser from a
/// `SettingsScreen`, without rendering it. The first hop, `RootView` itself, is
/// not reachable from here (its `destination` is private); it is covered by
/// static review and by the device check N3.
@MainActor
final class SettingsRefreshTokenWiringTests: XCTestCase {

  func testSettingsPassesItsRefreshTokenToBudgets() {
    let screen = makeScreen(refreshToken: 7)

    XCTAssertEqual(screen.budgetsScreen()?.refreshToken, 7)
  }

  /// A new generation must reach the Budgets row, not only the first value.
  /// The two screens share their stores, so the only difference between the
  /// two Budgets values is the token.
  func testSettingsPassesEachNewRefreshTokenToBudgets() {
    let budgets = FakeBudgetStore()
    let insights = FakeInsightsStore()
    let before = makeScreen(refreshToken: 7, budgets: budgets, insights: insights).budgetsScreen()
    let after = makeScreen(refreshToken: 8, budgets: budgets, insights: insights).budgetsScreen()


    XCTAssertNotEqual(before, after)
    XCTAssertEqual(after?.refreshToken, 8)
  }

  func testOmittedRefreshTokenDefaultsToZero() {
    let screen = SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings()),
      budgetStore: FakeBudgetStore(),
      insightsStore: FakeInsightsStore()
    )

    XCTAssertEqual(screen.budgetsScreen()?.refreshToken, 0)
  }

  /// No Budgets row without both stores, so there is no destination to carry
  /// the token at all.
  func testBudgetsDestinationIsAbsentWithoutBothStores() {
    let screen = SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings()),
      insightsStore: FakeInsightsStore(),
      refreshToken: 7
    )

    XCTAssertNil(screen.budgetsScreen())
  }

  // MARK: - Helpers

  /// Fakes are built in the body, not as default arguments, because the
  /// fakes are main-actor isolated and a default argument is not.
  private func makeScreen(
    refreshToken: Int,
    budgets: FakeBudgetStore? = nil,
    insights: FakeInsightsStore? = nil
  ) -> SettingsScreen {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings()),
      budgetStore: budgets ?? FakeBudgetStore(),
      insightsStore: insights ?? FakeInsightsStore(),
      refreshToken: refreshToken
    )
  }
}
