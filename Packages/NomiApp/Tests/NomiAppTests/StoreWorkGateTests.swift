import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// The gates that keep a non-persistent or locked process from doing store work
/// (I-6 Amendment 1, steps A3 to A6), and the read-through preferences store
/// that holds the non-persistent process's writes off disk.
///
/// Every test builds its `StoreWorkEnvironment` the way production does, from
/// the real opening path (`NomiModelContainer.makeWithLocalFallback`), and builds
/// the app's wiring through `AppServices.make`, which `AppServices.shared` also
/// calls. A non-persistent source is therefore the real in-memory fallback, not a
/// stub. CloudKit always throws here, so no CloudKit container is constructed.
///
/// `@MainActor` because `AppServices` is. Every `UserDefaults` is a fresh suite,
/// removed in tearDown, so the test runner's domain is never written.
@MainActor
final class StoreWorkGateTests: XCTestCase {
  private var directory: URL!
  private var suiteNames: [String] = []
  /// Every container and environment a test makes, held to the end of the test.
  /// A `ModelContext` does not keep its container alive, so a container dropped
  /// while its context is in use traps.
  private var keepAlive: [AnyObject] = []
  /// How many times the opening path ran in the current test.
  private var opens = 0

  private struct Unavailable: Error {}

  private struct InertAccountProbe: CloudKitAccountProbing {
    func pauseReason() async -> SyncPauseReason? { nil }
    func accountChanges() -> AsyncStream<Void> {
      AsyncStream<Void> { continuation in continuation.finish() }
    }
  }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    opens = 0
  }

  override func tearDownWithError() throws {
    keepAlive = []
    for name in suiteNames {
      UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
    try? FileManager.default.removeItem(at: directory)
  }

  // MARK: - Helpers

  private func makeDefaults() throws -> UserDefaults {
    let name = UUID().uuidString
    suiteNames.append(name)
    return try XCTUnwrap(UserDefaults(suiteName: name))
  }

  /// The source as production builds it. The opening path is the real one, and
  /// `opens` counts how often it runs. `persistent: false` leaves the store file
  /// absent, so the path lands in the in-memory fallback through
  /// `.retryLater(.noStoreFile)`. `persistent: true` lets the local store open the
  /// file at `default.store`.
  private func makeSource(persistent: Bool, protectedDataAvailable: Bool = true) throws -> StoreWorkEnvironment {
    let storeURL = directory.appendingPathComponent("default.store")
    let scratch: URL = directory
    let recovery = try makeDefaults()
    let source = StoreWorkEnvironment(
      open: { [self] in
        opens += 1
        let local: () throws -> ModelContainer =
          persistent ? { try NomiModelContainer.makeLocal(at: storeURL) } : { throw Unavailable() }
        return NomiModelContainer.makeWithLocalFallback(
          cloudKit: { throw Unavailable() },
          local: local,
          storeURL: storeURL,
          recoveryDefaults: recovery,
          scratchDirectory: scratch)
      },
      protectedDataAvailable: { protectedDataAvailable })
    keepAlive.append(source)
    return source
  }

  /// The app's wiring, built by the factory `AppServices.shared` is built by.
  /// Only the fakes differ from production: credentials, the mail fetcher, the
  /// notification scheduler and the CloudKit probe.
  private func makeWiring(_ source: StoreWorkEnvironment, defaults: UserDefaults) -> AppEnvironment {
    let environment = AppServices.make(
      environment: source,
      defaults: defaults,
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler(),
      accountProbe: InertAccountProbe())
    keepAlive.append(environment)
    return environment
  }

  // MARK: - The gate that decides whether store work may run (c3, c4)

  /// (c4) Without protected data the store is not opened at all. The source
  /// counts every open, so a store constructed before protected data is known
  /// would be seen.
  func testNoStoreWorkWithoutProtectedData() throws {
    let source = try makeSource(persistent: true, protectedDataAvailable: false)

    XCTAssertFalse(source.mayRunStoreWork())
    XCTAssertEqual(opens, 0, "the store was opened before protected data was known to be available")
  }

  /// (c3) With protected data but an in-memory store, store work is not allowed.
  /// The store is opened once, to learn that it is not persistent.
  func testNoStoreWorkOnAnInMemoryStore() throws {
    let source = try makeSource(persistent: false)

    XCTAssertFalse(source.mayRunStoreWork())
    XCTAssertEqual(opens, 1)
  }

  /// A persistent store with protected data is the one case that runs.
  func testStoreWorkOnAPersistentStore() throws {
    let source = try makeSource(persistent: true)

    XCTAssertTrue(source.mayRunStoreWork())
  }

  // MARK: - The foreground sync gate (c3)

  /// (c3) On `.active`, a non-persistent store does not start the foreground
  /// sync. A persistent one does, exactly once. The source is the one the wiring
  /// is built from, so the gate and the wiring cannot disagree.
  func testForegroundSyncIsGatedOnPersistence() throws {
    let nonPersistent = try makeSource(persistent: false)
    _ = makeWiring(nonPersistent, defaults: try makeDefaults())
    var ran = 0

    AppServices.runForegroundSync(nonPersistent, didBecomeActive: { ran += 1 })
    XCTAssertEqual(ran, 0, "a non-persistent store never syncs in the foreground")

    let persistent = try makeSource(persistent: true)
    AppServices.runForegroundSync(persistent, didBecomeActive: { ran += 1 })
    XCTAssertEqual(ran, 1, "a persistent store syncs once on becoming active")
  }

  // MARK: - The preference choice, through the factory `shared` uses (c3)

  /// (c3) A non-persistent launch's first-run write stays in this launch. This
  /// launch reads it back, and nothing reaches `UserDefaults`.
  func testNonPersistentWiringWritesNoPreferenceToDefaults() throws {
    let defaults = try makeDefaults()
    let wiring = makeWiring(try makeSource(persistent: false), defaults: defaults)

    wiring.firstRun.completeFirstRun()

    XCTAssertEqual(wiring.firstRun.route, .main, "this launch reads back its own write")
    XCTAssertFalse(
      defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun),
      "nothing written by a non-persistent launch reaches UserDefaults")
  }

  /// The control for the test above. A persistent launch, built the same way,
  /// writes straight through, so the test above cannot pass by never writing.
  func testPersistentWiringWritesThePreferenceToDefaults() throws {
    let defaults = try makeDefaults()
    let wiring = makeWiring(try makeSource(persistent: true), defaults: defaults)

    wiring.firstRun.completeFirstRun()

    XCTAssertTrue(defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// The preference store on its own. Kept beside the wiring tests so a break
  /// in the choice shows up even if the wiring changes shape.
  func testPreferenceWritesStayOffDiskWhenNotPersistent() throws {
    let defaults = try makeDefaults()
    let key = PreferenceKey.hasCompletedFirstRun

    let store = AppServices.preferenceStore(persistent: false, defaults: defaults)
    store.set(true, forKey: key)

    XCTAssertTrue(store.bool(forKey: key), "the write is visible to this launch")
    XCTAssertFalse(defaults.bool(forKey: key), "nothing written by a non-persistent launch reaches UserDefaults")
  }

  // MARK: - Background (c4)

  #if !os(iOS)
    /// (c4) The background handler, through `runBackground`, with protected data
    /// unavailable: it completes `success: false`, never opens the store, and
    /// never runs sync.
    func testBackgroundTaskWithoutProtectedDataCompletesFalseAndNeverRunsStoreWork() async throws {
      let source = try makeSource(persistent: true, protectedDataAvailable: false)
      let record = BackgroundWorkRecord()
      var performed = 0

      await AppServices.runBackground(
        BackgroundWork(kind: .refresh, record: record),
        storeWork: source,
        perform: { _ in performed += 1 })

      XCTAssertEqual(record.recordedCompletions, [false], "completed exactly once, as a failure")
      XCTAssertEqual(performed, 0, "no sync ran")
      XCTAssertEqual(opens, 0, "the store was never opened")
    }

    /// (c3, c4) A non-persistent wiring: with protected data, the handler
    /// completes `success: false` and runs no sync. The store was opened once,
    /// which is how the gate learns it is not persistent.
    func testBackgroundTaskOnANonPersistentWiringCompletesFalseWithoutStoreWork() async throws {
      let source = try makeSource(persistent: false)
      _ = makeWiring(source, defaults: try makeDefaults())
      let record = BackgroundWorkRecord()
      var performed = 0

      await AppServices.runBackground(
        BackgroundWork(kind: .refresh, record: record),
        storeWork: source,
        perform: { _ in performed += 1 })

      XCTAssertEqual(record.recordedCompletions, [false])
      XCTAssertEqual(performed, 0, "a non-persistent store never syncs in the background")
    }

    /// The one case that syncs: protected data and a persistent store. Sync is
    /// responsible for its own completion, so none is recorded here.
    func testBackgroundTaskOnAPersistentStoreRunsSync() async throws {
      let source = try makeSource(persistent: true)
      let record = BackgroundWorkRecord()
      var performed = 0

      await AppServices.runBackground(
        BackgroundWork(kind: .refresh, record: record),
        storeWork: source,
        perform: { _ in performed += 1 })

      XCTAssertEqual(performed, 1)
      XCTAssertEqual(record.recordedCompletions, [], "the sync, not the gate, completes this task")
    }
  #endif

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
