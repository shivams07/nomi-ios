import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// XCTest, not swift-testing: a `ModelContainer` traps under the swift-testing
/// runner (see `InMemoryModelContainer`'s note in NomiCore).
///
/// The rules themselves are tested without a container in
/// `CategoryEditRulesTests` (NomiCore). These tests check that the store
/// applies them, writes nothing on refusal, and leaves transactions alone.
@MainActor
final class SwiftDataCategoryStoreUpdateTests: XCTestCase {

  /// Holds the container for the life of the test. A context does not keep its
  /// container alive, and a released container traps on the first fetch.
  private var keepAlive: ModelContainer?

  private struct Fixture {
    let store: SwiftDataCategoryStore
    let context: ModelContext
    let cache: InsightsCache
    let food: UUID
    let shopping: UUID
    let travel: UUID
  }

  private func makeFixture() throws -> Fixture {
    let container = try ModelContainer(
      for: NomiModelContainer.schema,
      configurations: [
        ModelConfiguration(
          schema: NomiModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    keepAlive = container
    let context = container.mainContext

    // Two system categories and one the user made, so every rule can be
    // exercised against a real neighbour.
    let food = NomiCore.Category(
      name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0)
    let shopping = NomiCore.Category(
      name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: true, sortIndex: 1)
    let travel = NomiCore.Category(
      name: "Travel", symbolName: "car", paletteSlot: 2, isSystem: false, sortIndex: 2)
    context.insert(food)
    context.insert(shopping)
    context.insert(travel)
    try context.save()

    let cache = InsightsCache()
    let store = SwiftDataCategoryStore(context: context, coordinator: WriteCoordinator(cache: cache))
    return Fixture(
      store: store, context: context, cache: cache,
      food: food.id, shopping: shopping.id, travel: travel.id)
  }

  private func row(_ id: UUID, in context: ModelContext) throws -> NomiCore.Category {
    try XCTUnwrap(
      try context.fetch(FetchDescriptor<NomiCore.Category>()).first { $0.id == id })
  }

  // MARK: success

  func testAnEditWritesNameSymbolAndColourAndPersists() throws {
    let f = try makeFixture()

    try f.store.update(f.travel, name: "Trips", symbolName: "airplane", paletteSlot: 5)

    let saved = try row(f.travel, in: f.context)
    XCTAssertEqual(saved.name, "Trips")
    XCTAssertEqual(saved.symbolName, "airplane")
    XCTAssertEqual(saved.paletteSlot, 5)
    XCTAssertFalse(saved.isSystem)
    XCTAssertEqual(saved.sortIndex, 2, "an edit does not move the category in the list")
  }

  func testTheStoredNameIsTrimmedAndWhitespaceCollapsed() throws {
    let f = try makeFixture()

    try f.store.update(f.travel, name: "  Trips \n  Abroad  ", symbolName: "car", paletteSlot: 2)

    XCTAssertEqual(try row(f.travel, in: f.context).name, "Trips Abroad")
  }

  func testKeepingOwnNameWithADifferentCaseIsAllowed() throws {
    // The edited row is excluded from the duplicate check. Without that, a
    // category could never be re-cased.
    let f = try makeFixture()

    try f.store.update(f.travel, name: "TRAVEL", symbolName: "car", paletteSlot: 2)

    XCTAssertEqual(try row(f.travel, in: f.context).name, "TRAVEL")
  }

  func testASystemCategoryCanBeRecoloured() throws {
    let f = try makeFixture()

    try f.store.update(f.food, name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 4)

    let saved = try row(f.food, in: f.context)
    XCTAssertEqual(saved.paletteSlot, 4)
    XCTAssertTrue(saved.isSystem, "editing does not change the system flag")
  }

  func testASystemCategoryCanBeRenamedAndStillCannotBeDeleted() throws {
    let f = try makeFixture()

    try f.store.update(f.food, name: "Groceries", symbolName: "cart", paletteSlot: 4)

    XCTAssertEqual(try row(f.food, in: f.context).name, "Groceries")
    XCTAssertThrowsError(try f.store.delete(f.food)) { error in
      XCTAssertEqual(error as? AppStoreError, .systemCategoryCannotBeDeleted)
    }
  }

  // MARK: refusals write nothing

  func testADuplicateNameIsRefusedAndTheRowIsUnchanged() throws {
    let f = try makeFixture()

    XCTAssertThrowsError(
      try f.store.update(f.travel, name: "  food & DINING ", symbolName: "airplane", paletteSlot: 5)
    ) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("food & DINING"))
    }

    let saved = try row(f.travel, in: f.context)
    XCTAssertEqual(saved.name, "Travel")
    XCTAssertEqual(saved.symbolName, "car", "a refused edit must not leave the icon half-written")
    XCTAssertEqual(saved.paletteSlot, 2, "a refused edit must not leave the colour half-written")
  }

  func testAnEmptyNameIsRefusedAndTheRowIsUnchanged() throws {
    let f = try makeFixture()

    XCTAssertThrowsError(try f.store.update(f.travel, name: " \n ", symbolName: "airplane", paletteSlot: 5)) {
      error in
      XCTAssertEqual(error as? CategoryUpdateError, .emptyName)
    }

    XCTAssertEqual(try row(f.travel, in: f.context).name, "Travel")
  }

  func testPaletteSlotsOutsideTheSevenHuesAreRefusedNotClamped() throws {
    let f = try makeFixture()

    for slot in [7, -1] {
      XCTAssertThrowsError(try f.store.update(f.travel, name: "Trips", symbolName: "car", paletteSlot: slot)) {
        error in
        XCTAssertEqual(error as? CategoryUpdateError, .paletteSlotOutOfRange(slot))
      }
    }

    let saved = try row(f.travel, in: f.context)
    XCTAssertEqual(saved.name, "Travel")
    XCTAssertEqual(saved.paletteSlot, 2)
  }

  func testTheEndsOfThePaletteAreAccepted() throws {
    let f = try makeFixture()

    try f.store.update(f.travel, name: "Trips", symbolName: "car", paletteSlot: 0)
    XCTAssertEqual(try row(f.travel, in: f.context).paletteSlot, 0)
    try f.store.update(f.travel, name: "Trips", symbolName: "car", paletteSlot: 6)
    XCTAssertEqual(try row(f.travel, in: f.context).paletteSlot, 6)
  }

  func testAnInvalidSymbolIsRefusedEvenWhenTheNameIsFine() throws {
    let f = try makeFixture()

    XCTAssertThrowsError(
      try f.store.update(f.travel, name: "Trips", symbolName: "air plane", paletteSlot: 5)
    ) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .invalidSymbolName("air plane"))
    }

    let saved = try row(f.travel, in: f.context)
    XCTAssertEqual(saved.name, "Travel", "the name is not written when the symbol is refused")
    XCTAssertEqual(saved.paletteSlot, 2)
  }

  func testAnUnknownIdIsNotFound() throws {
    let f = try makeFixture()
    let missing = UUID()

    XCTAssertThrowsError(try f.store.update(missing, name: "X", symbolName: "tag", paletteSlot: 0)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .notFound(missing))
    }
  }

  func testTheUncategorizedSentinelIsNotEditable() throws {
    // It is a display value for a nil `categoryID`, with no row. Editing it
    // must fail, or "Uncategorized" could be renamed or recoloured.
    let f = try makeFixture()
    let sentinel = NomiCore.Category.uncategorizedID

    XCTAssertThrowsError(try f.store.update(sentinel, name: "Other", symbolName: "tag", paletteSlot: 0)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .notFound(sentinel))
    }
    XCTAssertEqual(try f.context.fetch(FetchDescriptor<NomiCore.Category>()).count, 3, "no row was created")
  }

  // MARK: observer hook

  func testASuccessfulEditInvalidatesTheCacheOnce() throws {
    let f = try makeFixture()
    let before = f.cache.invalidationCount

    try f.store.update(f.travel, name: "Trips", symbolName: "airplane", paletteSlot: 5)

    XCTAssertEqual(f.cache.invalidationCount, before + 1)
  }

  func testARefusedEditDoesNotInvalidateTheCache() throws {
    let f = try makeFixture()
    let before = f.cache.invalidationCount

    XCTAssertThrowsError(try f.store.update(f.travel, name: "shopping", symbolName: "car", paletteSlot: 2))

    XCTAssertEqual(f.cache.invalidationCount, before)
  }

  // MARK: rules agree with the seed

  func testThePaletteBoundMatchesTheSeed() {
    // `CategoryEditRules` cannot read `CategorySeedSpec` (NomiApp), so the two
    // are pinned here. If the seed ever gains an eighth hue, this fails.
    XCTAssertEqual(CategoryEditRules.paletteSlotCount, CategorySeedSpec.slotCount)
  }
}

/// Kept apart from the class above because it builds `Transaction` rows. On
/// this Mac an XCTest that constructs a `Transaction` has exited on SIGTRAP,
/// which takes the rest of the run with it (see the XCTest Transaction note).
/// A separate class keeps that crash from hiding the rest.
@MainActor
final class SwiftDataCategoryStoreMoneyTests: XCTestCase {

  private var keepAlive: ModelContainer?

  /// An edit must not change any transaction. The amounts are unequal and
  /// uneven, so a mutation that moved money would change a value that is
  /// checked.
  func testAnEditLeavesEveryTransactionExactlyAsItWas() throws {
    let container = try ModelContainer(
      for: NomiModelContainer.schema,
      configurations: [
        ModelConfiguration(
          schema: NomiModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    keepAlive = container
    let context = container.mainContext

    let travel = NomiCore.Category(name: "Travel", symbolName: "car", paletteSlot: 2, sortIndex: 0)
    context.insert(travel)
    let hotel = NomiCore.Transaction(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "HOTEL BOOKING",
      normalizedDescription: "HOTEL BOOKING",
      amountMinor: 1_234_567,
      directionRaw: Direction.debit.rawValue,
      categoryID: travel.id,
      categorySourceRaw: CategorySource.manual.rawValue,
      accountID: UUID(),
      dedupeKey: "hotel"
    )
    let refund = NomiCore.Transaction(
      date: Date(timeIntervalSince1970: 1_700_086_400),
      descriptionText: "REFUND",
      normalizedDescription: "REFUND",
      amountMinor: 50_000,
      directionRaw: Direction.credit.rawValue,
      accountID: UUID(),
      dedupeKey: "refund"
    )
    context.insert(hotel)
    context.insert(refund)
    try context.save()

    let before = try context.fetch(FetchDescriptor<NomiCore.Transaction>())
      .map { ($0.id, $0.amountMinor, $0.directionRaw, $0.categoryID, $0.categorySourceRaw, $0.updatedAt) }

    let store = SwiftDataCategoryStore(
      context: context, coordinator: WriteCoordinator(cache: InsightsCache()))
    try store.update(travel.id, name: "Trips", symbolName: "airplane", paletteSlot: 5)

    let after = try context.fetch(FetchDescriptor<NomiCore.Transaction>())
      .map { ($0.id, $0.amountMinor, $0.directionRaw, $0.categoryID, $0.categorySourceRaw, $0.updatedAt) }
    XCTAssertEqual(before.count, 2)
    XCTAssertEqual(after.map(\.0), before.map(\.0))
    XCTAssertTrue(zip(before, after).allSatisfy { $0 == $1 }, "a category edit wrote to a transaction")
    XCTAssertEqual(after.first { $0.0 == hotel.id }?.1, 1_234_567)
    XCTAssertEqual(after.first { $0.0 == refund.id }?.1, 50_000)
  }
}
