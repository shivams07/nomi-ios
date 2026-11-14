import Foundation
import XCTest

@testable import NomiApp

/// The gates that keep a non-persistent or locked process from doing store work
/// (I-6 Amendment 1, steps A3 to A5), and the read-through preferences store
/// that holds the non-persistent process's writes off disk.
///
/// `@MainActor` because `AppServices` is. Every test uses its own
/// `InMemoryKeyValueStore` as the base, never `UserDefaults.standard`, so the
/// test runner's domain is never written.
@MainActor
final class StoreWorkGateTests: XCTestCase {
  // MARK: - mayRunStoreWork (c3, c4)

  /// (c4) Without protected data, the store is not consulted at all. The
  /// closure reading persistence is what would construct the store, so it must
  /// not run.
  func testNoStoreWorkWithoutProtectedData() {
    let allowed = AppServices.mayRunStoreWork(
      protectedDataAvailable: false,
      storeIsPersistent: {
        XCTFail("the store was consulted before protected data was known to be available")
        return true
      })
    XCTAssertFalse(allowed)
  }

  /// (c3) With protected data but an in-memory store, background sync is not
  /// allowed.
  func testNoStoreWorkOnAnInMemoryStore() {
    XCTAssertFalse(AppServices.mayRunStoreWork(protectedDataAvailable: true, storeIsPersistent: { false }))
  }

  /// A persistent store with protected data is the one case that runs.
  func testStoreWorkOnAPersistentStore() {
    XCTAssertTrue(AppServices.mayRunStoreWork(protectedDataAvailable: true, storeIsPersistent: { true }))
  }

  // MARK: - ReadThroughKeyValueStore (c3, preferences)

  /// A key never written here reads through to the base.
  func testReadsFallThroughToTheBase() {
    let base = InMemoryKeyValueStore()
    base.set(true, forKey: "flag")
    base.set(Data([1, 2, 3]), forKey: "blob")

    let store = ReadThroughKeyValueStore(reading: base)

    XCTAssertTrue(store.bool(forKey: "flag"))
    XCTAssertEqual(store.data(forKey: "blob"), Data([1, 2, 3]))
    XCTAssertFalse(store.bool(forKey: "unset"))
    XCTAssertNil(store.data(forKey: "unset"))
  }

  /// A write goes to the overlay only. After writing, the base still holds its
  /// old value, which is what the next, persistent launch will read.
  func testWritesNeverReachTheBase() {
    let base = InMemoryKeyValueStore()
    base.set(false, forKey: "flag")
    base.set(Data([9]), forKey: "blob")

    let store = ReadThroughKeyValueStore(reading: base)
    store.set(true, forKey: "flag")
    store.set(Data([7, 7]), forKey: "blob")

    XCTAssertTrue(store.bool(forKey: "flag"), "the write is visible to this launch")
    XCTAssertEqual(store.data(forKey: "blob"), Data([7, 7]))
    XCTAssertFalse(base.bool(forKey: "flag"), "the base is unchanged")
    XCTAssertEqual(base.data(forKey: "blob"), Data([9]), "the base is unchanged")
  }

  /// A written nil hides the base's value for that key, so a later read returns
  /// nil and not what was stored before.
  func testAWrittenNilHidesTheBaseValue() {
    let base = InMemoryKeyValueStore()
    base.set(Data([5]), forKey: "blob")

    let store = ReadThroughKeyValueStore(reading: base)
    store.set(nil, forKey: "blob")

    XCTAssertNil(store.data(forKey: "blob"), "a written nil shadows the base")
    XCTAssertEqual(base.data(forKey: "blob"), Data([5]), "and the base still holds its value")
  }
}
