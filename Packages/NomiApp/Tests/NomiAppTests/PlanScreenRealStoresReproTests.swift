#if os(macOS)
import AppKit
import NomiCore
@testable import NomiUI
import SwiftData
import SwiftUI
import XCTest

@testable import NomiApp

/// Reproduction for the Plan tab crash on device (PR #221, Lim). Hosts the real
/// `PlanScreen` with the real SwiftData stores, once with budgets and once empty,
/// and runs its first layout and model load. A trap in any store call on the
/// Plan path fails this test.
@MainActor
final class PlanScreenRealStoresReproTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  override func tearDown() {
    stacks.removeAll()
    super.tearDown()
  }

  private func seed(_ stack: InMemoryStack) {
    let food = NomiCore.Category(name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: false, sortIndex: 0)
    let shopping = NomiCore.Category(name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: false, sortIndex: 1)
    stack.context.insert(food)
    stack.context.insert(shopping)
    stack.context.insert(NomiCore.Budget(categoryID: food.id, amountMinor: 5_000_00))
    stack.context.insert(NomiCore.Budget(categoryID: shopping.id, amountMinor: 8_000_00))
    try? stack.context.save()
  }

  private func makeStores(withData: Bool) throws -> (InMemoryStack, InsightsCache, SwiftDataBudgetStore, SwiftDataInsightsStore, SwiftDataRecurringStore) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    if withData { seed(stack) }
    let cache = InsightsCache()
    let budgets = SwiftDataBudgetStore(context: stack.context, coordinator: WriteCoordinator(cache: cache))
    let insights = SwiftDataInsightsStore(context: stack.context, cache: cache)
    let recurring = SwiftDataRecurringStore(context: stack.context, cache: cache)
    return (stack, cache, budgets, insights, recurring)
  }

  func testModelLoadsWithRealStoresAndBudgets() throws {
    let (_, _, budgets, insights, recurring) = try makeStores(withData: true)
    let model = PlanModel(insightsStore: insights, recurringStore: recurring)
    model.load()
    XCTAssertNotNil(model.progress)
    _ = budgets
  }

  func testModelLoadsWithRealStoresAndNoData() throws {
    let (_, _, _, insights, recurring) = try makeStores(withData: false)
    let model = PlanModel(insightsStore: insights, recurringStore: recurring)
    model.load()
    XCTAssertNotNil(model.progress)
  }

  func testPlanScreenHostsWithRealStoresAndBudgets() throws {
    try host(withData: true)
  }

  func testPlanScreenHostsWithRealStoresAndNoData() throws {
    try host(withData: false)
  }

  private func host(withData: Bool) throws {
    let (stack, _, budgets, insights, recurring) = try makeStores(withData: withData)
    var settings = NotificationSettings(budgetAlertsEnabled: true)
    let screen = PlanScreen(
      budgetStore: budgets,
      insightsStore: insights,
      recurringStore: recurring,
      notificationSettings: Binding(get: { settings }, set: { settings = $0 }),
      isRequestingNotificationPermission: false,
      refreshToken: 0
    )
    .modelContainer(stack.container)
    let view = NSHostingView(rootView: screen)
    view.frame = NSRect(x: 0, y: 0, width: 402, height: 874)
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    for _ in 0..<8 {
      RunLoop.main.run(until: Date().addingTimeInterval(0.25))
      view.layoutSubtreeIfNeeded()
    }
    XCTAssertGreaterThan(view.subviews.count, 0)
  }
}
#endif
