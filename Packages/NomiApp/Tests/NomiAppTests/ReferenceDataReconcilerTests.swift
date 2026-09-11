import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// W1-1 (H1). A real container, its `mainContext`, and the reconciler
/// `AppEnvironment` builds.
///
/// Every test inserts the **later** row first. SwiftData promises no fetch
/// order, but insertion order is the likeliest accident, and a reconciler that
/// kept "whichever came back first" would pass a test that inserted the earlier
/// row first.
///
/// XCTest, because constructing the container under swift-testing traps (see
/// `InMemoryModelContainer`).
@MainActor
final class ReferenceDataReconcilerTests: XCTestCase {

  private static let earlier = Date(timeIntervalSince1970: 1_780_000_000)
  private static let later = Date(timeIntervalSince1970: 1_780_086_400)
  private static let stampTime = Date(timeIntervalSince1970: 1_789_000_000)

  // MARK: - Categories

  func testTwoDatedCategoriesSharingAnIDCollapseToTheEarlier() throws {
    let harness = try Harness()
    let id = UUID()
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: Self.later))
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: Self.earlier))
    try harness.context.save()

    let removed = try harness.reconciler.run()

    let rows = try harness.categories()
    XCTAssertEqual(removed, 1)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.createdAt, Self.earlier)
  }

  func testAnUndatedMemberIsStampedAndItsGroupIsLeftForTheNextPass() throws {
    let harness = try Harness()
    let id = UUID()
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: nil))
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: Self.earlier))
    try harness.context.save()

    XCTAssertEqual(try harness.reconciler.run(), 0)

    let rows = try harness.categories()
    XCTAssertEqual(rows.count, 2, "a group is not collapsed by the pass that dated one of its members")
    XCTAssertEqual(Set(rows.compactMap(\.createdAt)), [Self.earlier, Self.stampTime])

    // The pass after does collapse it, to the row that already had a date.
    XCTAssertEqual(try harness.reconciler.run(), 1)
    XCTAssertEqual(try harness.categories().map(\.createdAt), [Self.earlier])
  }

  /// Not in the unit's list of cases; it pins `stampSpacing`. With one shared
  /// `now()`, both copies would carry the same date and the next pass would
  /// keep whichever the fetch returned first — the tie the survivor rule cannot
  /// break.
  func testTwoUndatedCopiesAreStampedApartSoTheNextPassHasAnAnswer() throws {
    let harness = try Harness()
    let id = UUID()
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: nil))
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: nil))
    try harness.context.save()

    XCTAssertEqual(try harness.reconciler.run(), 0)

    let stamps = try harness.categories().compactMap(\.createdAt)
    XCTAssertEqual(stamps.count, 2)
    XCTAssertEqual(Set(stamps).count, 2, "two copies stamped with one instant are a tie")

    XCTAssertEqual(try harness.reconciler.run(), 1)
    XCTAssertEqual(try harness.categories().count, 1)
  }

  func testARenameOnTheLosingCopyIsCarriedOntoTheSurvivor() throws {
    let harness = try Harness()
    let spec = DefaultCategorySeed.specs[0]
    harness.context.insert(
      NomiCore.Category(
        id: spec.id, name: "Food", symbolName: spec.symbolName, paletteSlot: spec.paletteSlot,
        isSystem: true, sortIndex: spec.sortIndex, createdAt: Self.later))
    harness.context.insert(
      NomiCore.Category(
        id: spec.id, name: spec.name, symbolName: spec.symbolName, paletteSlot: spec.paletteSlot,
        isSystem: true, sortIndex: spec.sortIndex, createdAt: Self.earlier))
    try harness.context.save()

    XCTAssertEqual(try harness.reconciler.run(), 1)

    let rows = try harness.categories()
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows.first?.createdAt, Self.earlier, "the survivor is still the earlier row")
    XCTAssertEqual(rows.first?.name, "Food", "and it carries the rename the later copy held")
  }

  // MARK: - Rules and budgets

  func testTwoRulesSharingAnIDCollapseToTheEarlier() throws {
    let harness = try Harness()
    let id = UUID()
    let category = UUID()
    harness.context.insert(
      Rule(id: id, pattern: "*PETSHOP*", categoryID: category, priority: 7, createdAt: Self.later))
    harness.context.insert(
      Rule(id: id, pattern: "*PETSHOP*", categoryID: category, priority: 3, createdAt: Self.earlier))
    try harness.context.save()

    XCTAssertEqual(try harness.reconciler.run(), 1)

    let rules = try harness.context.fetch(FetchDescriptor<Rule>())
    XCTAssertEqual(rules.count, 1)
    XCTAssertEqual(rules.first?.createdAt, Self.earlier)
    XCTAssertEqual(rules.first?.priority, 3)
  }

  func testTwoBudgetsForOneCategoryCollapseToTheEarlier() throws {
    let harness = try Harness()
    let category = UUID()
    let other = UUID()
    harness.context.insert(Budget(categoryID: category, amountMinor: 900_000, createdAt: Self.later))
    harness.context.insert(Budget(categoryID: category, amountMinor: 500_000, createdAt: Self.earlier))
    harness.context.insert(Budget(categoryID: other, amountMinor: 100_000, createdAt: Self.later))
    try harness.context.save()

    XCTAssertEqual(try harness.reconciler.run(), 1)

    let budgets = try harness.context.fetch(FetchDescriptor<Budget>())
    XCTAssertEqual(budgets.count, 2)
    XCTAssertEqual(budgets.filter { $0.categoryID == category }.map(\.amountMinor), [500_000])
    XCTAssertEqual(
      budgets.filter { $0.categoryID == other }.count, 1,
      "a budget alone in its category is not a duplicate")
  }

  // MARK: - didWrite

  func testARemovalDropsTheCache() throws {
    let harness = try Harness()
    let id = UUID()
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: Self.later))
    harness.context.insert(NomiCore.Category(id: id, name: "Pets", createdAt: Self.earlier))
    try harness.context.save()
    let before = harness.cache.generation

    try harness.reconciler.run()

    XCTAssertEqual(harness.cache.generation, before + 1)
  }

  /// The pass has work to do — a row to stamp — so "nothing happened" cannot be
  /// why the cache survives.
  func testAPassThatRemovesNothingDoesNotDropTheCache() throws {
    let harness = try Harness()
    harness.context.insert(NomiCore.Category(name: "Pets", createdAt: nil))
    try harness.context.save()
    let before = harness.cache.generation

    XCTAssertEqual(try harness.reconciler.run(), 0)

    XCTAssertEqual(harness.cache.generation, before)
    XCTAssertEqual(try harness.categories().first?.createdAt, Self.stampTime, "the pass did run")
  }

  // MARK: -

  @MainActor
  private struct Harness {
    let context: ModelContext
    let cache: InsightsCache
    let reconciler: ReferenceDataReconciler

    init() throws {
      let container = try ModelContainer(
        for: NomiModelContainer.schema,
        configurations: [
          ModelConfiguration(
            schema: NomiModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
      let cache = InsightsCache()
      let stamp = ReferenceDataReconcilerTests.stampTime
      self.context = container.mainContext
      self.cache = cache
      self.reconciler = ReferenceDataReconciler(
        context: container.mainContext,
        coordinator: WriteCoordinator(cache: cache),
        now: { stamp })
    }

    func categories() throws -> [NomiCore.Category] {
      try context.fetch(FetchDescriptor<NomiCore.Category>())
    }
  }
}
