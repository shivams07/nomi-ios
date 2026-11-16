import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// I-13 Amendment 1, B5 step 2. Every test runs on an in-memory store, a
/// `UserDefaults` suite and a temporary directory it made itself. None touches
/// the real store, `UserDefaults.standard`, the Keychain, or the host's
/// temporary directory beyond its own folder.
///
/// The order test observes the eraser's calls through one trace: the mail
/// disconnect, the credential delete, each store save, the alert removal and each
/// preference write. The saves, the alert removal and the preference writes also
/// record whether `Recovered/` is still on disk, so the file-removal order is
/// pinned by the trace too. The cache drop and the gate reopen go through seams on
/// the eraser, so the trace pins them as well.
/// The pipeline's lock is not observed directly: the save runs in the lock's body
/// by construction, and `PipelineEpochTests` (B5a) pins the lock.
@MainActor
final class DataEraserTests: XCTestCase {
  private var fixtures: [EraseFixture] = []

  override func tearDown() {
    for fixture in fixtures {
      try? FileManager.default.removeItem(at: fixture.root)
      fixture.suite.removePersistentDomain(forName: fixture.suiteName)
    }
    fixtures = []
    super.tearDown()
  }

  // MARK: - Order and completeness

  /// Every lettered step of B5 step 2 that the call makes, in the order it makes
  /// them. Step a reads the mode. Step b cancels the background requests, and
  /// step c is the disconnect and the credential delete. Steps d and e are the two
  /// saves, f is the alert removal, and g (the files) is seen as `recovered=no` on
  /// everything after f. Step h writes the erasable preferences, step i drops the
  /// caches, step j restarts first run, and step k reopens the gate. The last two
  /// steps are the eraser's own seams, so each records its event where the call is made.
  func testOrderOfOperations() async throws {
    let fixture = try await makeFixture()
    let seeded = try fixture.seedEveryModel()
    try fixture.plantRecovered()
    fixture.startRecording()
    let generationBefore = fixture.cache.generation

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    let erasable = PreferenceKey.erasable.map { "prefs.set \($0.key)" }
    XCTAssertEqual(
      fixture.trace.names,
      [
        "preflight.scope",  // a
        "submitter.cancelAll",  // b
        "fetcher.disconnect",  // c
        "credentials.delete",  // c: the mailbox layer's own delete, after the disconnect
        "prefs.set \(PreferenceKey.mailBackfillUnfinished)",  // c: the mailbox layer's write
        "credentials.delete",  // c: the erase's direct delete
        "store.save 1",  // d: every row deleted, one save
        "store.save 2",  // e: the reseed's own save
        "notifications.removeAllAlerts",  // f
      ] + erasable + [
        "caches.dropped",  // i
        "prefs.set \(PreferenceKey.hasCompletedFirstRun)",  // j
        "gate.reopened",  // k
      ],
      "each step ran once, in I-13 order, with nothing extra")

    let events = fixture.trace.events
    let alertsAt = try XCTUnwrap(events.firstIndex { EraseTrace.name(of: $0) == "notifications.removeAllAlerts" })
    for (index, event) in events.enumerated() {
      guard let state = EraseTrace.state(of: event) else { continue }
      XCTAssertEqual(
        state, index <= alertsAt ? "recovered=yes" : "recovered=no",
        "Recovered/ is removed after the alerts (step g), not before: \(event)")
    }
    XCTAssertEqual(
      fixture.saveSeam.categoriesAtCall.last, seeded.categoryIDs.count,
      "the seeds were back before the reseed's save (step e)")
    XCTAssertGreaterThan(fixture.cache.generation, generationBefore, "i: the cache generation moved")
    XCTAssertTrue(fixture.cache.isEmpty, "i: the cache holds nothing")
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "j: first run restarted")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "k: the gate reopened")
  }

  /// Every row of every model goes, and only the seeded categories and rules
  /// come back, with the same ids they had before.
  func testEveryModelEmptyThenSeedsBack() async throws {
    let fixture = try await makeFixture()
    let seeded = try fixture.seedEveryModel()

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0)
    XCTAssertEqual(try fixture.count(NomiCore.Account.self), 0)
    XCTAssertEqual(try fixture.count(NomiCore.Budget.self), 0)
    XCTAssertEqual(try fixture.count(BudgetAlertLog.self), 0)
    XCTAssertEqual(try fixture.count(AccountBinding.self), 0)
    XCTAssertEqual(try fixture.count(ColumnMappingRecord.self), 0)
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the user's category is gone and the seeds are back")
    XCTAssertEqual(try fixture.ruleIDs(), seeded.ruleIDs, "the user's rule is gone and the seeds are back")
  }

  /// Erasing twice in a row is safe: the second run finds the seeds already present.
  func testEraseTwiceInARowIsSafe() async throws {
    let fixture = try await makeFixture()
    let seeded = try fixture.seedEveryModel()

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0)
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs)
    XCTAssertEqual(try fixture.ruleIDs(), seeded.ruleIDs)
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate is open after the second erase")
  }

  // MARK: - Mail credential

  /// The fetcher's disconnect throws before the mailbox layer reaches its own
  /// credential delete. The erase deletes the credential itself, so it is gone.
  func testCredentialDeletedEvenWhenDisconnectThrows() async throws {
    let fixture = try await makeFixture(disconnect: .throwsError)
    try fixture.seedEveryModel()
    fixture.startRecording()

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    XCTAssertEqual(fixture.trace.count("credentials.delete"), 1, "the erase deleted the credential directly")
  }

  /// A disconnect that never returns cannot hold the erase open. It is abandoned
  /// after the timeout, and the credential is still deleted.
  func testADisconnectThatHangsIsAbandonedAfterTheTimeout() async throws {
    let fixture = try await makeFixture(disconnect: .hangs, disconnectTimeout: 0.2)
    try fixture.seedEveryModel()
    fixture.startRecording()

    let started = Date()
    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    let elapsed = Date().timeIntervalSince(started)

    XCTAssertLessThan(elapsed, 1.5, "the erase did not wait for the hung disconnect")
    XCTAssertEqual(fixture.trace.count("credentials.delete"), 1)
  }

  // MARK: - Files

  /// Recovered/, probe leftovers and report CSVs go. The store file, an unrelated
  /// file and a CSV-named text file are kept.
  func testFilesRemovedAndOthersKept() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    let fm = FileManager.default
    let recovered = fixture.recoveredURL
    let probe = fixture.tempDirectory.appendingPathComponent("nomi-store-probe-ABC", isDirectory: true)
    let reportA = fixture.tempDirectory.appendingPathComponent("nomi-report-2026-11-a.csv")
    let reportB = fixture.tempDirectory.appendingPathComponent("nomi-report-2026-10-b.csv")
    let notes = fixture.tempDirectory.appendingPathComponent("nomi-report-notes.txt")
    let unrelated = fixture.tempDirectory.appendingPathComponent("unrelated.txt")
    let liveStore = fixture.storeDirectory.appendingPathComponent("default.store")
    try fm.createDirectory(at: recovered, withIntermediateDirectories: true)
    try Data([1]).write(to: recovered.appendingPathComponent("default-20261101T000000Z.store"))
    try fm.createDirectory(at: probe, withIntermediateDirectories: true)
    try Data([2]).write(to: probe.appendingPathComponent("default.store"))
    try Data("a".utf8).write(to: reportA)
    try Data("b".utf8).write(to: reportB)
    try Data("n".utf8).write(to: notes)
    try Data("u".utf8).write(to: unrelated)
    try Data("live".utf8).write(to: liveStore)

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    XCTAssertFalse(fm.fileExists(atPath: recovered.path), "Recovered/ is removed")
    XCTAssertFalse(fm.fileExists(atPath: probe.path), "probe leftovers are removed")
    XCTAssertFalse(fm.fileExists(atPath: reportA.path), "a report CSV is removed")
    XCTAssertFalse(fm.fileExists(atPath: reportB.path), "a report CSV is removed")
    XCTAssertTrue(fm.fileExists(atPath: notes.path), "a nomi-report file that is not a CSV is kept")
    XCTAssertTrue(fm.fileExists(atPath: unrelated.path), "an unrelated file is kept")
    XCTAssertTrue(fm.fileExists(atPath: liveStore.path), "the live store file is not a file erase removes")
  }

  /// M2 (removing the files before the store save) survived the PR's own tests.
  /// `Recovered/` must still be on disk at each save, and gone once the erase returns.
  func testRecoveredFolderGoesOnlyAfterTheSaves() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    try fixture.plantRecovered()
    fixture.startRecording()

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    let saves = fixture.trace.events.filter { EraseTrace.name(of: $0).hasPrefix("store.save") }
    XCTAssertEqual(saves.count, 2, "both saves ran")
    XCTAssertEqual(
      saves.map { EraseTrace.state(of: $0) }, ["recovered=yes", "recovered=yes"],
      "Recovered/ is still there at both saves")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveredURL.path), "gone after the erase")
  }

  // MARK: - Preferences

  /// Every key in `PreferenceKey.erasable` is cleared, with the call for its kind.
  func testEveryErasableKeyCleared() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    let prefs = fixture.preferences
    for entry in PreferenceKey.erasable {
      switch entry.kind {
      case .bool: prefs.set(true, forKey: entry.key)
      case .data: prefs.set(Data([9]), forKey: entry.key)
      }
    }
    prefs.set(true, forKey: "other.unrelated")

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    for entry in PreferenceKey.erasable {
      switch entry.kind {
      case .bool: XCTAssertFalse(prefs.bool(forKey: entry.key), entry.key)
      case .data: XCTAssertNil(prefs.data(forKey: entry.key), entry.key)
      }
    }
    XCTAssertTrue(prefs.bool(forKey: "other.unrelated"), "a key outside the list is kept")
  }

  /// The two keys held in `UserDefaults.standard` go, through the suite the eraser
  /// was given. An unrelated key stays.
  func testStandardDefaultsKeysRemoved() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    for key in PreferenceKey.standardDefaultsErasable {
      fixture.suite.set(Data([3]), forKey: key)
    }
    fixture.suite.set(true, forKey: "other.x")

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    for key in PreferenceKey.standardDefaultsErasable {
      XCTAssertNil(fixture.suite.object(forKey: key), key)
    }
    XCTAssertTrue(fixture.suite.bool(forKey: "other.x"), "an unrelated defaults key is kept")
  }

  // MARK: - Scope and refusal

  /// `.inMemory` refuses before anything is touched. The only thing the call reads
  /// is the mode, and no spy sees a call.
  func testInMemoryRefusesAndTouchesNothing() async throws {
    let fixture = try await makeFixture(mode: .inMemory(reason: "retry later"))
    try fixture.seedEveryModel()
    XCTAssertEqual(fixture.eraser.scope, .unavailable(reason: "retry later"))
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("an in-memory launch must refuse")
    } catch let error as EraseError {
      XCTAssertEqual(error, .unavailable(reason: "retry later"))
    }

    XCTAssertEqual(fixture.trace.names, ["preflight.scope"], "the mode was read, and no spy was called")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 1, "the rows are still there")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing)
  }

  /// CloudKit reaches iCloud. Every other persistent state erases on this device only.
  func testScopePerStorageMode() async throws {
    let fixture = try await makeFixture()
    let cases: [(StorageMode, EraseScope)] = [
      (.cloudKit, .everywhere),
      (.cloudKitPaused(.noAccount), .thisDeviceOnly),
      (.cloudKitPaused(.restricted), .thisDeviceOnly),
      (.cloudKitPaused(.temporarilyUnavailable), .thisDeviceOnly),
      (.cloudKitPaused(.couldNotDetermine("probe")), .thisDeviceOnly),
      (.localOnly(reason: "schema"), .thisDeviceOnly),
      (.inMemory(reason: "gone"), .unavailable(reason: "gone")),
    ]
    for (mode, expected) in cases {
      fixture.mode.mode = mode
      XCTAssertEqual(fixture.eraser.scope, expected, "\(mode)")
    }
  }

  // MARK: - Busy

  /// A second erase while one holds the gate throws busy before anything is
  /// touched. The rows stay, and the holder keeps the gate.
  func testBusyMeansNothingErased() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    let holder = try await fixture.sync.beginErase()
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("an erase while the gate is held must throw busy")
    } catch let error as EraseError {
      XCTAssertEqual(error, .busy)
    }

    XCTAssertEqual(fixture.trace.names, ["preflight.scope"], "only the mode was read, and no spy was called")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 1, "no row was deleted")
    let stillHeld = await fixture.sync.isErasing
    XCTAssertTrue(stillHeld, "the first holder keeps the gate")
    await fixture.sync.endErase(holder)
  }

  // MARK: - Failures that still let the rest run

  /// The first store save fails, and the reseed's save succeeds. Everything else
  /// still runs and the erase throws incomplete. The reseed's save commits the
  /// row deletes that were still pending, so the rows are gone here.
  func testStoreSaveFailureAloneStillClearsTheRestAndThrowsIncomplete() async throws {
    let fixture = try await makeFixture(failingSaves: [1])
    try fixture.seedEveryModel()
    for key in PreferenceKey.standardDefaultsErasable {
      fixture.suite.set(Data([3]), forKey: key)
    }
    try fixture.plantRecovered()
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a failed save must throw incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }

    XCTAssertEqual(fixture.trace.count("store.save"), 2, "the reseed still ran its own save")
    // The disconnect succeeds here, so the mailbox layer deletes the credential
    // once and the erase deletes it again directly: two calls, both expected.
    XCTAssertEqual(fixture.trace.count("credentials.delete"), 2)
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1)
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0, "the reseed's save committed the row deletes")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveredURL.path), "files were still removed")
    XCTAssertNil(fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor), "preferences were still cleared")
    XCTAssertNil(fixture.suite.object(forKey: PreferenceKey.dismissedRecurringSeries), "defaults were still cleared")
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "the first-run route was still restarted")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate reopened after incomplete")
  }

  /// The reseed's save fails after the rows are gone. Everything else still runs
  /// and the erase throws incomplete. Each seed call saved on its own before this
  /// save ran, so the seeds are already on disk here. The test pins that the
  /// failure is reported, and that a retry leaves the same defaults in place.
  func testReseedSaveFailureRunsEverythingElseAndRetryRestoresDefaults() async throws {
    let fixture = try await makeFixture(failingSaves: [2])
    let seeded = try fixture.seedEveryModel()
    for key in PreferenceKey.standardDefaultsErasable {
      fixture.suite.set(Data([3]), forKey: key)
    }
    try fixture.plantRecovered()
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a failed reseed save must throw incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }

    XCTAssertEqual(fixture.trace.count("store.save"), 2, "both saves were attempted")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0, "the row deletes were saved first")
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the seeds are on disk")
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1, "alerts were still removed")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveredURL.path), "files were still removed")
    XCTAssertNil(fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor), "preferences were still cleared")
    XCTAssertNil(fixture.suite.object(forKey: PreferenceKey.dismissedRecurringSeries), "defaults were still cleared")
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "the first-run route was still restarted")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate reopened after incomplete")

    // A retry with the save working again has nothing left to delete, and it leaves the same defaults.
    fixture.saveSeam.failing = []
    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0)
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the retry leaves the same category ids")
    XCTAssertEqual(try fixture.ruleIDs(), seeded.ruleIDs, "the retry leaves the same rule ids")
  }

  /// A row delete throws part-way through the loop. The models before it were
  /// deleted in the context, and nothing saves them until the reseed's save, which
  /// commits them. The rest keep their rows. The erase throws incomplete, and a
  /// retry removes what is left.
  func testDeleteThatThrowsMidLoopLeavesTheRestForARetry() async throws {
    let fixture = try await makeFixture()
    let seeded = try fixture.seedEveryModel()
    try fixture.plantRecovered()
    // The fourth model in NomiSchemaV1.models: BudgetAlertLog. The first three are
    // Transaction, Category and Budget.
    fixture.deleteSeam.failAtCall = 4
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a delete that throws must end incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }

    XCTAssertEqual(fixture.deleteSeam.calls, 4, "the loop stopped at the failing model")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0, "deleted before the failure, committed later")
    XCTAssertEqual(try fixture.count(NomiCore.Budget.self), 0, "deleted before the failure, committed later")
    XCTAssertEqual(try fixture.count(BudgetAlertLog.self), 1, "the failing model keeps its row")
    XCTAssertEqual(try fixture.count(NomiCore.Account.self), 1, "a model after the failure keeps its row")
    XCTAssertEqual(try fixture.count(AccountBinding.self), 1, "a model after the failure keeps its row")
    XCTAssertEqual(try fixture.count(ColumnMappingRecord.self), 1, "a model after the failure keeps its row")
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the user's category went, and the seeds came back")
    XCTAssertEqual(
      try fixture.ruleIDs().count, seeded.ruleIDs.count + 1,
      "the rule step was not reached, so the user's rule stays")
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1, "alerts were still removed")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveredURL.path), "files were still removed")
    XCTAssertNil(fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor), "preferences were still cleared")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate reopened after incomplete")

    fixture.deleteSeam.failAtCall = nil
    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    XCTAssertEqual(try fixture.count(BudgetAlertLog.self), 0, "the retry removed the row that was left")
    XCTAssertEqual(try fixture.count(NomiCore.Account.self), 0)
    XCTAssertEqual(try fixture.count(AccountBinding.self), 0)
    XCTAssertEqual(try fixture.count(ColumnMappingRecord.self), 0)
    XCTAssertEqual(try fixture.ruleIDs(), seeded.ruleIDs, "the retry removed the user's rule")
  }

  /// The token reopens the gate on every exit: a clean erase, a disconnect that
  /// throws, and an erase that ends incomplete.
  func testEndEraseRunsOnEveryPath() async throws {
    let clean = try await makeFixture()
    try await withTestTimeout(seconds: 30) { [eraser = clean.eraser!] in try await eraser.eraseEverything() }
    let cleanOpen = await clean.sync.isErasing
    XCTAssertFalse(cleanOpen, "clean erase")

    let disconnectFails = try await makeFixture(disconnect: .throwsError)
    try await withTestTimeout(seconds: 30) { [eraser = disconnectFails.eraser!] in try await eraser.eraseEverything() }
    let disconnectOpen = await disconnectFails.sync.isErasing
    XCTAssertFalse(disconnectOpen, "disconnect throws")

    let saveFails = try await makeFixture(failingSaves: [1, 2])
    do {
      try await withTestTimeout(seconds: 30) { [eraser = saveFails.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a failed save must throw incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }
    let saveOpen = await saveFails.sync.isErasing
    XCTAssertFalse(saveOpen, "save fails")
  }

  // MARK: - Credential and caches (Andrews' ruling on PR #217)

  /// A Keychain delete that fails is not success. Every other step still runs, the
  /// gate reopens, and the erase reports incomplete.
  func testCredentialDeleteFailureRunsEverythingElseAndThrowsIncomplete() async throws {
    let fixture = try await makeFixture(credentialDeleteFails: true)
    let seeded = try fixture.seedEveryModel()
    for key in PreferenceKey.standardDefaultsErasable {
      fixture.suite.set(Data([3]), forKey: key)
    }
    try fixture.plantRecovered()
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a credential that cannot be deleted must throw incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }

    XCTAssertEqual(
      fixture.trace.count("credentials.delete"), 2,
      "the mailbox layer's delete and the erase's direct delete were both attempted")
    XCTAssertEqual(fixture.trace.count("store.save"), 2, "the store was still saved")
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1, "alerts were still removed")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0, "rows were still deleted")
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the seeds came back")
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveredURL.path), "files were still removed")
    XCTAssertNil(fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor), "preferences were still cleared")
    XCTAssertNil(
      fixture.suite.object(forKey: PreferenceKey.dismissedRecurringSeries), "defaults were still cleared")
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "first run was still restarted")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate reopened")
  }

  /// Every aggregate cache is dropped. The generation moves and the cache is empty.
  func testAggregateCachesAreDroppedByErase() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    let before = fixture.cache.generation

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    XCTAssertGreaterThan(fixture.cache.generation, before, "the cache generation moved")
    XCTAssertTrue(fixture.cache.isEmpty, "the cache holds nothing after erase")
  }

  // MARK: - Production defaults on a real store

  /// The fixtures pass their own `deleteRows` and `saveStore`, so a no-op default
  /// would pass every test above. This erase takes the defaults on an on-disk
  /// store. The rows are then read back through a second container on the same file.
  func testDefaultDeleteAndSaveEmptyARealStore() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DataEraserDefaults-\(UUID().uuidString)", isDirectory: true)
    let storeDirectory = root.appendingPathComponent("store", isDirectory: true)
    let tempDirectory = root.appendingPathComponent("temp", isDirectory: true)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storeURL = storeDirectory.appendingPathComponent("default.store")
    let suiteName = "DataEraserDefaults.\(UUID().uuidString)"
    let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { suite.removePersistentDomain(forName: suiteName) }

    let container = try NomiModelContainer.makeLocal(at: storeURL)
    let context = container.mainContext
    try DefaultCategorySeed.apply(in: context)
    try DefaultRuleSeed.apply(in: context)
    try context.save()
    let seededCategories = Set(try context.fetch(FetchDescriptor<NomiCore.Category>()).map(\.id))
    let seededRules = Set(try context.fetch(FetchDescriptor<Rule>()).map(\.id))
    let account = NomiCore.Account(displayName: "Savings")
    context.insert(account)
    context.insert(
      NomiCore.Transaction(
        date: Date(),
        descriptionText: "SALARY",
        merchantName: "Employer",
        normalizedDescription: "SALARY",
        amountMinor: 1_000_000))
    context.insert(NomiCore.Budget(categoryID: UUID(), amountMinor: 50_000))
    context.insert(BudgetAlertLog(categoryID: UUID(), periodKey: "2026-11"))
    context.insert(AccountBinding(senderDomain: "bank.example", cardFragment: "1234", accountID: account.id))
    context.insert(ColumnMappingRecord(formatSignature: "sig", bankLabel: "Bank", mappingJSON: "{}"))
    context.insert(NomiCore.Category(name: "Mine"))
    context.insert(Rule(pattern: "MINE", categoryID: UUID(), priority: 1))
    try context.save()

    let trace = EraseTrace()
    let credentials = TracingCredentials(trace: trace)
    let preferences = TracingPreferences(trace: trace)
    let mailStack = MailStack(
      fetcher: EraseFetcher(disconnect: .succeeds, trace: trace),
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: preferences
    )
    let pipeline = IngestPipeline(store: EmptyPipelineStore())
    let sync = AppSyncCoordinator(
      mail: mailStack, pipeline: pipeline, submitter: TracingSubmitter(trace: trace))
    preferences.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    let firstRun = FirstRunGate(store: preferences)
    let service = await mailStack.service
    let eraser = DataEraser(
      container: container,
      storageMode: { .cloudKit },
      sync: sync,
      pipeline: pipeline,
      mail: service,
      credentials: credentials,
      notifications: TracingNotifications(trace: trace),
      preferences: preferences,
      standardDefaults: suite,
      firstRun: firstRun,
      writes: WriteCoordinator(cache: InsightsCache()),
      storeDirectory: storeDirectory,
      tempDirectory: tempDirectory,
      disconnectTimeout: 5
    )

    try await withTestTimeout(seconds: 30) { [eraser] in try await eraser.eraseEverything() }

    let reopenedContainer = try NomiModelContainer.makeLocal(at: storeURL)
    let reopened = ModelContext(reopenedContainer)
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<NomiCore.Transaction>()), 0, "transactions are gone")
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<NomiCore.Budget>()), 0, "budgets are gone")
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<BudgetAlertLog>()), 0, "alert logs are gone")
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<NomiCore.Account>()), 0, "accounts are gone")
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<AccountBinding>()), 0, "bindings are gone")
    XCTAssertEqual(try reopened.fetchCount(FetchDescriptor<ColumnMappingRecord>()), 0, "mappings are gone")
    XCTAssertEqual(
      Set(try reopened.fetch(FetchDescriptor<NomiCore.Category>()).map(\.id)), seededCategories,
      "on disk, only the seeded categories remain")
    XCTAssertEqual(
      Set(try reopened.fetch(FetchDescriptor<Rule>()).map(\.id)), seededRules,
      "on disk, only the seeded rules remain")
    withExtendedLifetime(container) {}
    withExtendedLifetime(reopenedContainer) {}
  }

  // MARK: - Fixtures

  private func makeFixture(
    mode: StorageMode = .cloudKit,
    disconnect: EraseFetcher.Disconnect = .succeeds,
    disconnectTimeout: TimeInterval = 5,
    failingSaves: Set<Int> = [],
    credentialDeleteFails: Bool = false
  ) async throws -> EraseFixture {
    let fixture = try EraseFixture(
      mode: mode, disconnect: disconnect, disconnectTimeout: disconnectTimeout, failingSaves: failingSaves,
      credentialDeleteFails: credentialDeleteFails)
    await fixture.wire()
    fixtures.append(fixture)
    return fixture
  }
}

// MARK: - Fixture

/// Everything one erase test needs. Held by the test class, so the container
/// outlives every use of it (a dropped `ModelContainer` traps).
@MainActor
private final class EraseFixture {
  let root: URL
  let storeDirectory: URL
  let tempDirectory: URL
  let suiteName: String
  let suite: UserDefaults
  let trace: EraseTrace
  let mode: ModeBox
  let stack: InMemoryStack
  let preferences: TracingPreferences
  let sync: AppSyncCoordinator
  let firstRun: FirstRunGate
  let mailStack: MailStack
  let credentials: TracingCredentials
  let notifications: TracingNotifications
  let pipeline: IngestPipeline
  let writes: WriteCoordinator
  let disconnectTimeout: TimeInterval
  let cache: InsightsCache
  let saveSeam = SaveSeam()
  let deleteSeam = DeleteSeam()
  /// Set by `wire()`, which must run before any test calls it.
  private(set) var eraser: DataEraser!

  init(
    mode: StorageMode, disconnect: EraseFetcher.Disconnect, disconnectTimeout: TimeInterval,
    failingSaves: Set<Int>, credentialDeleteFails: Bool
  ) throws {
    let trace = EraseTrace()
    self.trace = trace
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("DataEraserTests-\(UUID().uuidString)", isDirectory: true)
    let storeDirectory = root.appendingPathComponent("store", isDirectory: true)
    let tempDirectory = root.appendingPathComponent("temp", isDirectory: true)
    try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    self.root = root
    self.storeDirectory = storeDirectory
    self.tempDirectory = tempDirectory

    let recovered = storeDirectory.appendingPathComponent("Recovered", isDirectory: true)
    trace.setStamp {
      FileManager.default.fileExists(atPath: recovered.path) ? "recovered=yes" : "recovered=no"
    }

    suiteName = "DataEraserTests.\(UUID().uuidString)"
    suite = UserDefaults(suiteName: suiteName)!
    let modeBox = ModeBox(mode)
    self.mode = modeBox

    let stack = try InMemoryStack()
    self.stack = stack

    let fetcher = EraseFetcher(disconnect: disconnect, trace: trace)
    let credentials = TracingCredentials(trace: trace, deleteFails: credentialDeleteFails)
    let preferences = TracingPreferences(trace: trace)
    self.preferences = preferences
    let notifications = TracingNotifications(trace: trace)
    let cache = InsightsCache()
    self.cache = cache
    let writes = WriteCoordinator(cache: cache)
    let pipeline = IngestPipeline(store: EmptyPipelineStore())
    let mailStack = MailStack(
      fetcher: fetcher,
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: preferences
    )
    let sync = AppSyncCoordinator(
      mail: mailStack,
      pipeline: pipeline,
      submitter: TracingSubmitter(trace: trace)
    )
    self.sync = sync

    // The first-run flag is set, so the route starts on `.main` and the restart is visible.
    preferences.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    let firstRun = FirstRunGate(store: preferences)
    self.firstRun = firstRun

    self.mailStack = mailStack
    self.credentials = credentials
    self.notifications = notifications
    self.pipeline = pipeline
    self.writes = writes
    self.disconnectTimeout = disconnectTimeout
    saveSeam.failing = failingSaves
  }

  /// `MailStack` is an actor, so its connection service is read with `await`.
  /// The eraser is built here, once the fixture is complete.
  func wire() async {
    let service = await mailStack.service
    let trace = self.trace
    let modeBox = self.mode
    let saveSeam = self.saveSeam
    let deleteSeam = self.deleteSeam
    let sync = self.sync
    let writes = self.writes
    eraser = DataEraser(
      container: stack.container,
      storageMode: {
        trace.record("preflight.scope")
        return modeBox.mode
      },
      sync: sync,
      pipeline: pipeline,
      mail: service,
      credentials: credentials,
      notifications: notifications,
      preferences: preferences,
      standardDefaults: suite,
      firstRun: firstRun,
      writes: writes,
      storeDirectory: storeDirectory,
      tempDirectory: tempDirectory,
      disconnectTimeout: disconnectTimeout,
      deleteRows: { model, context in
        deleteSeam.calls += 1
        if deleteSeam.calls == deleteSeam.failAtCall { throw FixtureDeleteError.failed }
        try context.delete(model: model)
      },
      saveStore: { context in
        saveSeam.calls += 1
        let number = saveSeam.calls
        saveSeam.categoriesAtCall.append((try? context.fetchCount(FetchDescriptor<NomiCore.Category>())) ?? -1)
        trace.record("store.save \(number)", stamped: true)
        if saveSeam.failing.contains(number) { throw FixtureSaveError.failed }
        try context.save()
      },
      dropCaches: { [writes] in
        writes.didWrite(affectedCategoryIDs: [])
        trace.record("caches.dropped")
      },
      reopenGate: { [sync] token in
        await sync.endErase(token)
        trace.record("gate.reopened")
      }
    )
  }

  var firstRunRoute: AppRoute { firstRun.route }

  var recoveredURL: URL { storeDirectory.appendingPathComponent("Recovered", isDirectory: true) }

  func startRecording() {
    trace.reset()
  }

  /// `Recovered/` beside the store, with one file in it, as a failed open leaves it.
  func plantRecovered() throws {
    try FileManager.default.createDirectory(at: recoveredURL, withIntermediateDirectories: true)
    try Data([1]).write(to: recoveredURL.appendingPathComponent("default-20261101T000000Z.store"))
  }

  /// Applies the real seeds, saves, then adds one row of every other model and
  /// one user category and rule. Returns the seeded ids, before the user rows.
  @discardableResult
  func seedEveryModel() throws -> (categoryIDs: Set<UUID>, ruleIDs: Set<UUID>) {
    let context = stack.context
    try DefaultCategorySeed.apply(in: context)
    try DefaultRuleSeed.apply(in: context)
    try context.save()
    let seeded = try (categoryIDs: categoryIDs(), ruleIDs: ruleIDs())

    let account = NomiCore.Account(displayName: "Savings")
    context.insert(account)
    context.insert(
      NomiCore.Transaction(
        date: Date(),
        descriptionText: "SALARY",
        merchantName: "Employer",
        normalizedDescription: "SALARY",
        amountMinor: 1_000_000))
    context.insert(NomiCore.Budget(categoryID: UUID(), amountMinor: 50_000))
    context.insert(BudgetAlertLog(categoryID: UUID(), periodKey: "2026-11"))
    context.insert(AccountBinding(senderDomain: "bank.example", cardFragment: "1234", accountID: account.id))
    context.insert(ColumnMappingRecord(formatSignature: "sig", bankLabel: "Bank", mappingJSON: "{}"))
    context.insert(NomiCore.Category(name: "Mine"))
    context.insert(Rule(pattern: "MINE", categoryID: UUID(), priority: 1))
    try context.save()
    return seeded
  }

  func count<M: PersistentModel>(_ model: M.Type) throws -> Int {
    try stack.context.fetchCount(FetchDescriptor<M>())
  }

  func categoryIDs() throws -> Set<UUID> {
    Set(try stack.context.fetch(FetchDescriptor<NomiCore.Category>()).map(\.id))
  }

  func ruleIDs() throws -> Set<UUID> {
    Set(try stack.context.fetch(FetchDescriptor<Rule>()).map(\.id))
  }
}

/// The mode the eraser reads at each call, changed by a test between calls.
@MainActor
private final class ModeBox {
  var mode: StorageMode
  init(_ mode: StorageMode) { self.mode = mode }
}

/// Counts the eraser's store saves, and fails the ones named in `failing`.
/// Save 1 is the row delete, and save 2 is the reseed's.
@MainActor
private final class SaveSeam {
  var calls = 0
  var failing: Set<Int> = []
  /// The category count each save saw, in call order.
  var categoriesAtCall: [Int] = []
}

/// Counts the eraser's per-model deletes, and fails the call numbered `failAtCall`.
@MainActor
private final class DeleteSeam {
  var calls = 0
  var failAtCall: Int?
}

/// Every event the spies record, in order. A stamped event carries the disk state
/// at the step, in brackets after its name: `store.save 1 [recovered=yes]`.
private final class EraseTrace: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []
  private var stamp: (@Sendable () -> String)?

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  /// The event names, without their stamps, in order.
  var names: [String] {
    events.map(EraseTrace.name(of:))
  }

  /// Set once by the fixture, before any step is recorded.
  func setStamp(_ stamp: @escaping @Sendable () -> String) {
    lock.lock()
    self.stamp = stamp
    lock.unlock()
  }

  func record(_ event: String, stamped: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    if stamped, let stamp {
      recorded.append("\(event) [\(stamp())]")
    } else {
      recorded.append(event)
    }
  }

  func reset() {
    lock.lock()
    recorded = []
    lock.unlock()
  }

  /// The events whose name is `name`, or starts with it followed by a space, so
  /// `store.save` counts both saves.
  func count(_ name: String) -> Int {
    names.filter { $0 == name || $0.hasPrefix(name + " ") }.count
  }

  static func name(of event: String) -> String {
    guard let open = event.range(of: " [") else { return event }
    return String(event[..<open.lowerBound])
  }

  static func state(of event: String) -> String? {
    guard let open = event.range(of: " ["), event.hasSuffix("]") else { return nil }
    return String(event[open.upperBound..<event.index(before: event.endIndex)])
  }
}

private enum FixtureSaveError: Error { case failed }
private enum FixtureDeleteError: Error { case failed }

/// The mail fetcher's disconnect is the only call erase makes into it. `hangs`
/// ignores cancellation, the way a sync blocked on NWIMAPFetcher's busy lock does.
private final class EraseFetcher: MailFetching, @unchecked Sendable {
  enum Disconnect: Sendable {
    case succeeds
    case throwsError
    case hangs
  }

  private let behaviour: Disconnect
  private let trace: EraseTrace

  init(disconnect: Disconnect, trace: EraseTrace) {
    self.behaviour = disconnect
    self.trace = trace
  }

  func connect(_ credentials: IMAPCredentials) async throws {}

  func disconnect() async throws {
    trace.record("fetcher.disconnect")
    switch behaviour {
    case .succeeds:
      return
    case .throwsError:
      throw MailError.connectionFailed
    case .hangs:
      try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
  }

  func selectMailbox(_ name: String) async throws -> MailboxState {
    MailboxState(name: name, uidValidity: 1, uidNext: 1)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] { [] }
  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] { [] }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] { [] }
  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] { [] }
}

private enum FixtureCredentialError: Error { case failed }

private final class TracingCredentials: MailCredentialStoring, @unchecked Sendable {
  private let trace: EraseTrace
  private let deleteFails: Bool

  init(trace: EraseTrace, deleteFails: Bool = false) {
    self.trace = trace
    self.deleteFails = deleteFails
  }

  func save(_ credentials: IMAPCredentials) throws {}
  func load() throws -> IMAPCredentials? { nil }

  func delete() throws {
    trace.record("credentials.delete")
    if deleteFails { throw FixtureCredentialError.failed }
  }
}

private final class TracingPreferences: KeyValueStoring, @unchecked Sendable {
  private let base = InMemoryKeyValueStore()
  private let trace: EraseTrace

  init(trace: EraseTrace) { self.trace = trace }

  func bool(forKey key: String) -> Bool { base.bool(forKey: key) }

  func set(_ value: Bool, forKey key: String) {
    trace.record("prefs.set \(key)", stamped: true)
    base.set(value, forKey: key)
  }

  func data(forKey key: String) -> Data? { base.data(forKey: key) }

  func set(_ value: Data?, forKey key: String) {
    trace.record("prefs.set \(key)", stamped: true)
    base.set(value, forKey: key)
  }
}

private final class TracingNotifications: BudgetNotificationScheduling, @unchecked Sendable {
  private let trace: EraseTrace

  init(trace: EraseTrace) { self.trace = trace }

  @discardableResult
  func requestAuthorization() async throws -> Bool { false }

  func isAuthorized() async -> Bool { false }
  func schedule(_ alert: BudgetAlert) async throws {}

  func removeAllAlerts() async {
    trace.record("notifications.removeAllAlerts", stamped: true)
  }
}

private final class TracingSubmitter: BackgroundTaskSubmitting, @unchecked Sendable {
  private let trace: EraseTrace

  init(trace: EraseTrace) { self.trace = trace }

  func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval) {}

  func cancelAll() {
    trace.record("submitter.cancelAll")
  }
}
