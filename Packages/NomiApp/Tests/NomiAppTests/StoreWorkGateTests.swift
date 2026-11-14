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

  // MARK: - The background handler's real gate (c4, mutant M3b)

  #if !os(iOS)
    /// (c4) The background handler, driven through the production
    /// `runBackground`, with protected data unavailable: it completes `success:
    /// false`, never asks the store for persistence, and never runs sync. The
    /// protected-data answer is read from `protectedDataSource`, so a mutant that
    /// hard-codes `true` at that call site is caught here.
    func testBackgroundTaskWithoutProtectedDataCompletesFalseAndNeverRunsStoreWork() async {
      let original = AppServices.protectedDataSource
      AppServices.protectedDataSource = { false }
      defer { AppServices.protectedDataSource = original }

      let record = BackgroundWorkRecord()
      let work = BackgroundWork(kind: .refresh, record: record)
      var performed = 0

      await AppServices.runBackground(
        work,
        storeIsPersistent: {
          XCTFail("the store was consulted before protected data was known to be available")
          return true
        },
        perform: { _ in performed += 1 })

      XCTAssertEqual(record.recordedCompletions, [false], "completed exactly once, as a failure")
      XCTAssertEqual(performed, 0, "no sync ran")
    }

    /// With protected data but a non-persistent store, the handler completes
    /// `success: false` and does not sync.
    func testBackgroundTaskOnAnInMemoryStoreCompletesFalseAndDoesNotSync() async {
      let original = AppServices.protectedDataSource
      AppServices.protectedDataSource = { true }
      defer { AppServices.protectedDataSource = original }

      let record = BackgroundWorkRecord()
      var performed = 0

      await AppServices.runBackground(
        BackgroundWork(kind: .refresh, record: record),
        storeIsPersistent: { false },
        perform: { _ in performed += 1 })

      XCTAssertEqual(record.recordedCompletions, [false])
      XCTAssertEqual(performed, 0)
    }

    /// The one case that syncs: protected data and a persistent store. Sync is
    /// responsible for its own completion, so none is recorded here.
    func testBackgroundTaskOnAPersistentStoreRunsSync() async {
      let original = AppServices.protectedDataSource
      AppServices.protectedDataSource = { true }
      defer { AppServices.protectedDataSource = original }

      let record = BackgroundWorkRecord()
      var performed = 0

      await AppServices.runBackground(
        BackgroundWork(kind: .refresh, record: record),
        storeIsPersistent: { true },
        perform: { _ in performed += 1 })

      XCTAssertEqual(performed, 1)
      XCTAssertEqual(record.recordedCompletions, [], "the sync, not the gate, completes this task")
    }
  #endif

  // MARK: - The foreground gate (c3, mutant M4)

  /// (c3) On `.active`, a non-persistent store does not start the foreground
  /// sync. A persistent one does, exactly once.
  func testForegroundSyncIsGatedOnPersistence() {
    var ran = 0
    AppServices.runForegroundSync(
      storeIsPersistent: { false },
      didBecomeActive: { ran += 1 })
    XCTAssertEqual(ran, 0, "a non-persistent store never syncs in the foreground")

    AppServices.runForegroundSync(
      storeIsPersistent: { true },
      didBecomeActive: { ran += 1 })
    XCTAssertEqual(ran, 1, "a persistent store syncs once on becoming active")
  }

  // MARK: - Preferences (c3, mutant M5)

  /// (c3) A non-persistent launch's preference writes stay off `UserDefaults`,
  /// and this launch still reads them back. Uses its own suite, so the test
  /// runner's domain is untouched.
  func testPreferenceWritesStayOffDiskWhenNotPersistent() throws {
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = PreferenceKey.hasCompletedFirstRun

    let store = AppServices.preferenceStore(persistent: false, defaults: defaults)
    store.set(true, forKey: key)

    XCTAssertTrue(store.bool(forKey: key), "the write is visible to this launch")
    XCTAssertFalse(defaults.bool(forKey: key), "nothing written by a non-persistent launch reaches UserDefaults")
  }

  /// A persistent launch writes straight to `UserDefaults`, as before R7.
  func testPreferenceWritesReachDiskWhenPersistent() throws {
    let suite = UUID().uuidString
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let key = PreferenceKey.hasCompletedFirstRun

    AppServices.preferenceStore(persistent: true, defaults: defaults).set(true, forKey: key)

    XCTAssertTrue(defaults.bool(forKey: key))
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
