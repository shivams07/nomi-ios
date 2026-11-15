import Foundation
import NomiCore
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// R8b, step 2 and step 4. A budget store refuses an amount outside `AmountRules`
/// before any read or write, and removal is `removeBudget` alone. XCTest on a
/// stored `InMemoryStack` (see `InMemoryStack`): a container returned without being
/// held traps under SwiftData.
@MainActor
final class BudgetStoreAmountTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let food = UUID()
  private let travel = UUID()

  private func makeStore() throws -> (SwiftDataBudgetStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let store = SwiftDataBudgetStore(
      context: stack.context,
      coordinator: WriteCoordinator(cache: InsightsCache()))
    return (store, stack.context)
  }

  /// Zero, negative and one paisa over the bound: each throws `.outOfRange`, and the
  /// budget already there keeps its amount. Zero used to remove it.
  func testSetBudgetRefusesOutOfRangeAndChangesNothing() throws {
    let (store, _) = try makeStore()
    try store.setBudget(categoryID: food, amountMinor: 500_000)

    for amount in [0, -1, 100_000_000_001] {
      XCTAssertThrowsError(try store.setBudget(categoryID: food, amountMinor: amount)) { error in
        XCTAssertEqual(error as? AmountValidationError, .outOfRange(amountMinor: amount), "amount \(amount)")
      }
    }

    let budgets = try store.budgets()
    XCTAssertEqual(budgets.map { $0.amountMinor }, [500_000], "a refused set changed or removed the budget")
  }

  func testSetBudgetAcceptsTheBounds() throws {
    let (store, _) = try makeStore()
    try store.setBudget(categoryID: food, amountMinor: 1)
    try store.setBudget(categoryID: travel, amountMinor: 100_000_000_000)

    let stored = Set(try store.budgets().map { $0.amountMinor })
    XCTAssertEqual(stored, [1, 100_000_000_000])
  }

  func testRemoveBudgetStillRemoves() throws {
    let (store, _) = try makeStore()
    try store.setBudget(categoryID: food, amountMinor: 500_000)

    try store.removeBudget(categoryID: food)

    XCTAssertTrue(try store.budgets().isEmpty)
  }

  /// The fake is what the previews and UI tests use. It must refuse exactly what the
  /// real store refuses, or a preview would show a Save the app does not have.
  func testFakeBudgetStoreAgrees() throws {
    let fake = FakeBudgetStore(budgets: [])
    try fake.setBudget(categoryID: food, amountMinor: 500_000)

    for amount in [0, -1, 100_000_000_001] {
      XCTAssertThrowsError(try fake.setBudget(categoryID: food, amountMinor: amount)) { error in
        XCTAssertEqual(error as? AmountValidationError, .outOfRange(amountMinor: amount), "amount \(amount)")
      }
    }
    XCTAssertEqual(fake.storedBudgets.map { $0.amountMinor }, [500_000])

    try fake.setBudget(categoryID: travel, amountMinor: 1)
    try fake.setBudget(categoryID: UUID(), amountMinor: 100_000_000_000)
    XCTAssertEqual(fake.storedBudgets.count, 3)
    XCTAssertEqual(fake.storedBudgets.filter { $0.categoryID == travel }.map { $0.amountMinor }, [1])
  }
}
