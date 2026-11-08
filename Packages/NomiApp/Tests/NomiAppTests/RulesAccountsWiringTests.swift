import NomiCore
import NomiPreview
import SwiftData
import SwiftUI
import XCTest

@testable import NomiUI

/// D1 `rules-accounts-wire`. The Rules editor's Account picker was empty in the
/// running app because `SettingsScreen` built `RulesScreen` without `accounts:`.
/// These tests pin what reaches `RulesScreen`'s initialiser from
/// `SettingsScreen`. The `@Query` in `RootView` that supplies the live list
/// needs the app's container and is not reachable from here; that link is
/// covered by static review and the simulator check, not by this file.
@MainActor
final class RulesAccountsWiringTests: XCTestCase {

  func testSettingsPassesItsAccountsToRules() throws {
    let context = try makeContext()
    let checking = NomiCore.Account(displayName: "Checking", institution: "Bank A", lastFour: "1234")
    let savings = NomiCore.Account(displayName: "Savings", institution: "Bank A", lastFour: "5678")
    context.insert(checking)
    context.insert(savings)
    try context.save()

    let screen = makeScreen(accounts: [checking, savings])
    let rules = screen.rulesScreen()

    XCTAssertEqual(rules.accounts.count, 2)
    XCTAssertEqual(rules.accounts.map(\.id), [checking.id, savings.id])
  }

  /// The default keeps the picker at "Any" and matches every preview, which
  /// construct `SettingsScreen` without an account list.
  func testOmittedAccountsDefaultToEmpty() {
    let screen = SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings())
    )

    XCTAssertTrue(screen.rulesScreen().accounts.isEmpty)
  }

  // MARK: - Helpers

  private func makeScreen(accounts: [NomiCore.Account]) -> SettingsScreen {
    SettingsScreen(
      mailConnectionService: FakeMailConnectionService(),
      fileImportService: FakeFileImportService(),
      categoryStore: FakeCategoryStore(),
      ruleStore: FakeRuleStore(),
      notificationSettings: .constant(NotificationSettings()),
      accounts: accounts
    )
  }

  private func makeContext() throws -> ModelContext {
    let schema = Schema([NomiCore.Account.self])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    return container.mainContext
  }
}
