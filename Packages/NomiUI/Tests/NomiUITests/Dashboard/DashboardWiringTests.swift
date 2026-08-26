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
}
