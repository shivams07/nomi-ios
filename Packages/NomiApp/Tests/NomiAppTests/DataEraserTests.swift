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
/// The order test observes the mail disconnect, the credential delete, the store
/// save, the alert removal and the preference writes through one trace. The
/// sync gate is the real `AppSyncCoordinator`, and its `cancelAll` lands in the
/// same trace. The pipeline's lock is not observed directly: the save runs in
/// the lock's body by construction, and `PipelineEpochTests` (B5a) pins the lock.
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

  /// The recorded order: cancel the background requests, disconnect mail, delete
  /// the credential, save the store, remove alerts, write preferences, and end
  /// with the first-run flag cleared.
  func testOrderOfOperations() async throws {
    let fixture = try await makeFixture()
    try fixture.seedEveryModel()
    fixture.startRecording()

    try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }

    let events = fixture.trace.events
    assertInOrder(
      events,
      [
        "submitter.cancelAll",
        "fetcher.disconnect",
        "credentials.delete",
        "store.save",
        "notifications.removeAllAlerts",
        "prefs.set",
      ])
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "restartAfterErase ran")
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
    let recovered = fixture.storeDirectory.appendingPathComponent("Recovered", isDirectory: true)
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

  /// `.inMemory` refuses before anything is touched: no gate, no call to any spy.
  func testInMemoryRefusesAndTouchesNothing() async throws {
    let fixture = try await makeFixture(mode: .inMemory(reason: "retry later"))
    try fixture.seedEveryModel()
    fixture.startRecording()

    XCTAssertEqual(fixture.eraser.scope, .unavailable(reason: "retry later"))
    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("an in-memory launch must refuse")
    } catch let error as EraseError {
      XCTAssertEqual(error, .unavailable(reason: "retry later"))
    }

    XCTAssertEqual(fixture.trace.events, [], "no spy saw a call")
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

    XCTAssertEqual(fixture.trace.events, [], "nothing was called")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 1, "no row was deleted")
    let stillHeld = await fixture.sync.isErasing
    XCTAssertTrue(stillHeld, "the first holder keeps the gate")
    await fixture.sync.endErase(holder)
  }

  // MARK: - Save failure and the token

  /// The store save fails. Everything else is still cleared, the erase throws
  /// incomplete, and the gate reopens.
  func testSaveFailureStillClearsTheRestAndThrowsIncomplete() async throws {
    let fixture = try await makeFixture(saveFails: true)
    try fixture.seedEveryModel()
    for key in PreferenceKey.standardDefaultsErasable {
      fixture.suite.set(Data([3]), forKey: key)
    }
    let recovered = fixture.storeDirectory.appendingPathComponent("Recovered", isDirectory: true)
    try FileManager.default.createDirectory(at: recovered, withIntermediateDirectories: true)
    fixture.startRecording()

    do {
      try await withTestTimeout(seconds: 30) { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
      XCTFail("a failed save must throw incomplete")
    } catch let error as EraseError {
      XCTAssertEqual(error, .incomplete)
    }

    // The disconnect succeeds here, so the mailbox layer deletes the credential
    // once and the erase deletes it again directly: two calls, both expected.
    XCTAssertEqual(fixture.trace.count("credentials.delete"), 2)
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recovered.path), "files were still removed")
    XCTAssertNil(fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor), "preferences were still cleared")
    XCTAssertNil(fixture.suite.object(forKey: PreferenceKey.dismissedRecurringSeries), "defaults were still cleared")
    XCTAssertEqual(fixture.firstRunRoute, .onboarding(.welcome), "the first-run route was still restarted")
    let erasing = await fixture.sync.isErasing
    XCTAssertFalse(erasing, "the gate reopened after incomplete")
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

    let saveFails = try await makeFixture(saveFails: true)
    do {
      try await withTestTimeout(seconds: 30) { [eraser = saveFails.eraser!] in try await eraser.eraseEverything() }
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
    let recovered = fixture.storeDirectory.appendingPathComponent("Recovered", isDirectory: true)
    try FileManager.default.createDirectory(at: recovered, withIntermediateDirectories: true)
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
    XCTAssertTrue(fixture.trace.events.contains("store.save"), "the store was still saved")
    XCTAssertEqual(fixture.trace.count("notifications.removeAllAlerts"), 1, "alerts were still removed")
    XCTAssertEqual(try fixture.count(NomiCore.Transaction.self), 0, "rows were still deleted")
    XCTAssertEqual(try fixture.categoryIDs(), seeded.categoryIDs, "the seeds came back")
    XCTAssertFalse(FileManager.default.fileExists(atPath: recovered.path), "files were still removed")
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

  // MARK: - Fixtures

  private func makeFixture(
    mode: StorageMode = .cloudKit,
    disconnect: EraseFetcher.Disconnect = .succeeds,
    disconnectTimeout: TimeInterval = 5,
    saveFails: Bool = false,
    credentialDeleteFails: Bool = false
  ) async throws -> EraseFixture {
    let fixture = try EraseFixture(
      mode: mode, disconnect: disconnect, disconnectTimeout: disconnectTimeout, saveFails: saveFails,
      credentialDeleteFails: credentialDeleteFails)
    await fixture.wire()
    fixtures.append(fixture)
    return fixture
  }

  /// Each name in `expected` appears in `events`, in that order, with other events between.
  private func assertInOrder(_ events: [String], _ expected: [String], file: StaticString = #filePath, line: UInt = #line) {
    var cursor = 0
    for name in expected {
      guard let hit = events[cursor...].firstIndex(where: { $0 == name || ($0.hasPrefix(name + " ")) }) else {
        XCTFail("expected \(name) after position \(cursor) in \(events)", file: file, line: line)
        return
      }
      cursor = hit + 1
    }
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
  let saveFails: Bool
  let cache: InsightsCache
  /// Set by `wire()`, which must run before any test calls it.
  private(set) var eraser: DataEraser!

  init(
    mode: StorageMode, disconnect: EraseFetcher.Disconnect, disconnectTimeout: TimeInterval, saveFails: Bool,
    credentialDeleteFails: Bool
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
    self.saveFails = saveFails
  }

  /// `MailStack` is an actor, so its connection service is read with `await`.
  /// The eraser is built here, once the fixture is complete.
  func wire() async {
    let service = await mailStack.service
    let trace = self.trace
    let saveFails = self.saveFails
    let modeBox = self.mode
    eraser = DataEraser(
      container: stack.container,
      storageMode: { modeBox.mode },
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
      saveStore: { context in
        trace.record("store.save")
        if saveFails { throw FixtureSaveError.failed }
        try context.save()
      }
    )
  }

  var firstRunRoute: AppRoute { firstRun.route }

  func startRecording() {
    trace.reset()
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

/// Every event the spies record, in order.
private final class EraseTrace: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func record(_ event: String) {
    lock.lock()
    recorded.append(event)
    lock.unlock()
  }

  func reset() {
    lock.lock()
    recorded = []
    lock.unlock()
  }

  func count(_ event: String) -> Int {
    events.filter { $0 == event }.count
  }
}

private enum FixtureSaveError: Error { case failed }

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
    trace.record("prefs.set \(key)")
    base.set(value, forKey: key)
  }

  func data(forKey key: String) -> Data? { base.data(forKey: key) }

  func set(_ value: Data?, forKey key: String) {
    trace.record("prefs.set \(key)")
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
    trace.record("notifications.removeAllAlerts")
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
