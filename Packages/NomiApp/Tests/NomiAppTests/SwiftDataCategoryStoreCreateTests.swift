import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// `create` applies the rules `update` applies, before anything is written.
/// The rules themselves are tested without a container in
/// `CategoryEditRulesTests` (NomiCore). These tests check that the store
/// applies them to a new row, stores the normalised name, and writes nothing
/// on refusal.
///
/// XCTest, not swift-testing: a `ModelContainer` traps under the swift-testing
/// runner (see `InMemoryModelContainer`'s note in NomiCore).
@MainActor
final class SwiftDataCategoryStoreCreateTests: XCTestCase {

  /// Holds the container for the life of the test. A context does not keep its
  /// container alive, and a released container traps on the first fetch.
  private var keepAlive: ModelContainer?

  private struct Fixture {
    let store: SwiftDataCategoryStore
    let context: ModelContext
    let cache: InsightsCache
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
    context.insert(
      NomiCore.Category(
        name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0))
    context.insert(
      NomiCore.Category(
        name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: true, sortIndex: 1))
    context.insert(
      NomiCore.Category(
        name: "Travel", symbolName: "car", paletteSlot: 2, isSystem: false, sortIndex: 2))
    try context.save()

    let cache = InsightsCache()
    let store = SwiftDataCategoryStore(context: context, coordinator: WriteCoordinator(cache: cache))
    return Fixture(store: store, context: context, cache: cache)
  }

  /// Every category as (name, symbol, slot, sortIndex). A refused create must
  /// leave this exactly as it was.
  private func snapshot(_ context: ModelContext) throws -> [String] {
    try context.fetch(FetchDescriptor<NomiCore.Category>())
      .map { "\($0.name)|\($0.symbolName)|\($0.paletteSlot)|\($0.sortIndex)" }
      .sorted()
  }

  // MARK: success

  func testAUniqueNameIsCreatedAndPersisted() throws {
    let f = try makeFixture()

    let created = try f.store.create(name: "Pets", symbolName: "heart", paletteSlot: 3)

    XCTAssertEqual(created.name, "Pets")
    XCTAssertEqual(created.symbolName, "heart")
    XCTAssertEqual(created.paletteSlot, 3)
    XCTAssertFalse(created.isSystem)
    XCTAssertEqual(created.sortIndex, 3, "a new category goes after the last one")
    let rows = try f.context.fetch(FetchDescriptor<NomiCore.Category>())
    XCTAssertEqual(rows.count, 4)
    XCTAssertTrue(rows.contains { $0.id == created.id && $0.name == "Pets" })
  }

  func testTheStoredNameIsTheNormalisedName() throws {
    let f = try makeFixture()

    let created = try f.store.create(name: "  Home \n  Office  ", symbolName: "house", paletteSlot: 4)

    XCTAssertEqual(created.name, "Home Office")
    let saved = try f.context.fetch(FetchDescriptor<NomiCore.Category>()).first { $0.id == created.id }
    XCTAssertEqual(saved?.name, "Home Office", "the raw padded name must not be stored")
  }

  func testTheEndsOfThePaletteAreAcceptedOnCreate() throws {
    let f = try makeFixture()

    XCTAssertEqual(try f.store.create(name: "Low", symbolName: "tag", paletteSlot: 0).paletteSlot, 0)
    XCTAssertEqual(try f.store.create(name: "High", symbolName: "tag", paletteSlot: 6).paletteSlot, 6)
  }

  func testASuccessfulCreateInvalidatesTheCacheOnce() throws {
    let f = try makeFixture()
    let before = f.cache.invalidationCount

    _ = try f.store.create(name: "Pets", symbolName: "heart", paletteSlot: 3)

    XCTAssertEqual(f.cache.invalidationCount, before + 1)
  }

  func testACreatedNameIsAnExistingNameForTheNextCreate() throws {
    // The rule reads the rows as they are now, so a row created a moment ago
    // is a neighbour for the next create.
    let f = try makeFixture()
    _ = try f.store.create(name: "Pets", symbolName: "heart", paletteSlot: 3)

    XCTAssertThrowsError(try f.store.create(name: "pets", symbolName: "heart", paletteSlot: 3)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("pets"))
    }
  }

  // MARK: refusals write nothing

  func testACaseInsensitiveDuplicateIsRefusedAndNothingIsWritten() throws {
    // The same refusal the editor shows: a name that differs from an existing
    // one only by case. Without this store-side check, the editor's guard is
    // the only thing between a bypass and a second "Food & Dining".
    let f = try makeFixture()
    let before = try snapshot(f.context)
    let invalidations = f.cache.invalidationCount

    XCTAssertThrowsError(try f.store.create(name: "food & DINING", symbolName: "tag", paletteSlot: 5)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("food & DINING"))
    }

    XCTAssertEqual(try snapshot(f.context), before, "a refused create must not write a row")
    XCTAssertEqual(f.cache.invalidationCount, invalidations, "a refused create must not invalidate the cache")
  }

  func testAWhitespacePaddedDuplicateIsRefusedAndNothingIsWritten() throws {
    let f = try makeFixture()
    let before = try snapshot(f.context)
    let invalidations = f.cache.invalidationCount

    XCTAssertThrowsError(try f.store.create(name: "  Travel \n", symbolName: "car", paletteSlot: 2)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("Travel"))
    }

    XCTAssertEqual(try snapshot(f.context), before)
    XCTAssertEqual(f.cache.invalidationCount, invalidations)
  }

  func testAnEmptyNameIsRefusedAndNothingIsWritten() throws {
    let f = try makeFixture()
    let before = try snapshot(f.context)
    let invalidations = f.cache.invalidationCount

    XCTAssertThrowsError(try f.store.create(name: " \n\t ", symbolName: "tag", paletteSlot: 0)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .emptyName)
    }

    XCTAssertEqual(try snapshot(f.context), before)
    XCTAssertEqual(f.cache.invalidationCount, invalidations)
  }

  func testASlotOutsideTheSevenHuesIsRefusedNotClampedAndNothingIsWritten() throws {
    // The old create clamped 7 to 6 and -1 to 0, so a refused slot used to be
    // stored as a different colour. Both must now be refused, and no row made.
    let f = try makeFixture()
    let before = try snapshot(f.context)
    let invalidations = f.cache.invalidationCount

    for slot in [7, -1] {
      XCTAssertThrowsError(try f.store.create(name: "Pets", symbolName: "heart", paletteSlot: slot)) { error in
        XCTAssertEqual(error as? CategoryUpdateError, .paletteSlotOutOfRange(slot))
      }
    }

    XCTAssertEqual(try snapshot(f.context), before)
    XCTAssertEqual(f.cache.invalidationCount, invalidations)
  }

  func testAnInvalidSymbolIsRefusedAndNothingIsWritten() throws {
    let f = try makeFixture()
    let before = try snapshot(f.context)
    let invalidations = f.cache.invalidationCount

    XCTAssertThrowsError(try f.store.create(name: "Pets", symbolName: "air plane", paletteSlot: 3)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .invalidSymbolName("air plane"))
    }

    XCTAssertEqual(try snapshot(f.context), before)
    XCTAssertEqual(f.cache.invalidationCount, invalidations)
  }
}

/// Kept apart from the class above because it builds `Transaction` rows. An
/// XCTest that constructs a `Transaction` has been seen to exit on SIGTRAP,
/// which takes the rest of the run with it. A separate class keeps that crash
/// from hiding the rest.
@MainActor
final class SwiftDataCategoryStoreCreateMoneyTests: XCTestCase {

  private var keepAlive: ModelContainer?

  /// A create must not change any transaction, including a refused one. The
  /// amounts are unequal, so a mutation that moved money would change a value
  /// that is checked.
  func testACreateLeavesEveryTransactionExactlyAsItWas() throws {
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
    _ = try store.create(name: "Trips", symbolName: "airplane", paletteSlot: 5)
    XCTAssertThrowsError(try store.create(name: "travel", symbolName: "car", paletteSlot: 2))

    let after = try context.fetch(FetchDescriptor<NomiCore.Transaction>())
      .map { ($0.id, $0.amountMinor, $0.directionRaw, $0.categoryID, $0.categorySourceRaw, $0.updatedAt) }
    XCTAssertEqual(before.count, 2)
    XCTAssertEqual(after.map(\.0), before.map(\.0))
    XCTAssertTrue(zip(before, after).allSatisfy { $0 == $1 }, "a category create wrote to a transaction")
    XCTAssertEqual(after.first { $0.0 == hotel.id }?.1, 1_234_567)
    XCTAssertEqual(after.first { $0.0 == refund.id }?.1, 50_000)
  }
}
