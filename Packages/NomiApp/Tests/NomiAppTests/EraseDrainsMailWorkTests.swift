import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// Erase all data waits for mail work that the eraser did not start itself: a
/// sync from Connect Mail's "Check now", and a backfill from First scan. Both
/// reach `MailStack.service` directly, so `AppSyncCoordinator.activeWork` never
/// counted them, and the eraser used to delete while they were still writing.
///
/// The two kinds are handled differently. A plain sync is waited for. A backfill
/// is cancelled, because a First scan runs for minutes and an erase should not
/// wait for it. Either way nothing may write after the delete.
///
/// Each test holds one sync or backfill inside its first search, starts an erase
/// while it is held, and checks that the erase has not deleted, that a new sync
/// or backfill is refused, and that nothing writes after the erase returns. The
/// log records the ingest spy, the held search's return and the delete seam, so
/// the order is observed rather than inferred.
///
/// Every await is bounded by `withTestTimeout`. The held search ignores
/// cancellation unless a test says otherwise, so only the test's release ends it.
@MainActor
final class EraseDrainsMailWorkTests: XCTestCase {
  private var fixtures: [EraseDrainFixture] = []

  override func tearDown() async throws {
    // A test that failed early must not leave a held task behind.
    for fixture in fixtures {
      await fixture.fetcher.release.open()
      fixture.cleanUp()
    }
    fixtures = []
    try await super.tearDown()
  }

  // MARK: - Check now

  /// A "Check now" sync is held in its first search when the erase begins. The
  /// erase waits for it. Its one batch is ingested before the rows go, and
  /// nothing it writes lands after the erase has returned.
  func testEraseWaitsForACheckNowSyncAndNothingIsWrittenAfterIt() async throws {
    let fixture = try await makeFixture()
    let mail = fixture.mail
    let check = Task { try await mail.service.syncNow() }
    let entered = fixture.fetcher.entered
    try await withTestTimeout { await entered.wait() }

    let erase = Task { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    try await waitUntilErasing(fixture.coordinator)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertNil(
      fixture.log.index(of: EraseDrainEvent.delete),
      "the erase deleted while the Check now sync was still running")

    do {
      _ = try await mail.service.syncNow()
      XCTFail("a sync that starts during the erase must be refused")
    } catch is CancellationError {
      // expected: the gate is closed to new mail work
    }

    await fixture.fetcher.release.open()
    _ = try await withTestTimeout { try await check.value }
    try await withTestTimeout { try await erase.value }

    let ingestedAt = try XCTUnwrap(
      fixture.log.index(of: EraseDrainEvent.ingest),
      "the held sync did not reach its batch")
    let deletedAt = try XCTUnwrap(fixture.log.index(of: EraseDrainEvent.delete))
    XCTAssertLessThan(ingestedAt, deletedAt, "the sync's transaction landed after the rows were deleted")
    XCTAssertEqual(fixture.log.count(of: EraseDrainEvent.ingest), 1)
    try await assertNothingWritesAfterErase(fixture)
  }

  // MARK: - First scan

  /// A backfill from First scan is held in its first search when the erase
  /// begins, and that search does not honour cancellation. Erase cancels the scan,
  /// but the held search has to be released before the scan can stop. So the
  /// erase waits for the search to return, and the delete comes after that. The
  /// cancelled scan then fetches nothing, so it ingests nothing.
  func testEraseDrainsACancelledBackfillBeforeTheDeleteAndNothingIsWrittenAfterIt() async throws {
    let fixture = try await makeFixture()
    let mail = fixture.mail
    let scan = Task { try await mail.service.startBackfill(months: 6) }
    let entered = fixture.fetcher.entered
    try await withTestTimeout { await entered.wait() }
    let markerDuringScan = await mail.backfillIsUnfinished
    XCTAssertTrue(markerDuringScan, "setup: the held backfill has set the unfinished marker")

    let erase = Task { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    try await waitUntilErasing(fixture.coordinator)
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertNil(
      fixture.log.index(of: EraseDrainEvent.delete),
      "the erase deleted while the backfill's search was still held")

    do {
      _ = try await mail.service.startBackfill(months: 6)
      XCTFail("a backfill that starts during the erase must be refused")
    } catch is CancellationError {
      // expected: the gate is closed to new mail work
    }

    await fixture.fetcher.release.open()
    try await scanEndsCancelled(scan)
    try await withTestTimeout { try await erase.value }

    let returnedAt = try XCTUnwrap(
      fixture.log.index(of: EraseDrainEvent.searchReturned),
      "the held search never returned")
    let deletedAt = try XCTUnwrap(fixture.log.index(of: EraseDrainEvent.delete))
    XCTAssertLessThan(returnedAt, deletedAt, "the delete ran before the backfill's search had stopped")
    XCTAssertEqual(
      fixture.log.count(of: EraseDrainEvent.ingest), 0,
      "a cancelled backfill fetches nothing, so it ingests nothing")
    try await assertNothingWritesAfterErase(fixture)
  }

  /// A First scan whose search honours cancellation is running when the erase
  /// begins. The erase cancels it, the search stops at once, and the erase
  /// succeeds. It does not return busy, and it does not wait out the scan.
  func testEraseCancelsARunningFirstScanAndSucceedsWithoutBusy() async throws {
    let fixture = try await makeFixture(honoursCancellation: true)
    let mail = fixture.mail
    let scan = Task { try await mail.service.startBackfill(months: 6) }
    let entered = fixture.fetcher.entered
    try await withTestTimeout { await entered.wait() }

    let erase = Task { [eraser = fixture.eraser!] in try await eraser.eraseEverything() }
    // A bounded wait, shorter than the eraser's 30 s busy deadline. Busy here would
    // mean the scan was waited for, and this test exists to show it is not.
    try await withTestTimeout(seconds: 5) { try await erase.value }

    try await scanEndsCancelled(scan)
    let returnedAt = try XCTUnwrap(
      fixture.log.index(of: EraseDrainEvent.searchReturned),
      "the cancelled search never returned")
    let deletedAt = try XCTUnwrap(fixture.log.index(of: EraseDrainEvent.delete))
    XCTAssertLessThan(returnedAt, deletedAt, "the delete ran before the cancelled scan had stopped")
    XCTAssertEqual(fixture.log.count(of: EraseDrainEvent.ingest), 0)
    try await assertNothingWritesAfterErase(fixture)
  }

  // MARK: - Busy

  /// A mail sync that does not stop by the deadline makes the erase throw busy.
  /// This is checked at the coordinator, because the eraser's own wait is 30 s.
  /// Both gates reopen on that path, so mail work is admitted again once the held
  /// sync finishes. The erase steps after the wait are covered by the two tests above.
  func testAMailSyncThatDoesNotStopMakesEraseBusyAndReopensMail() async throws {
    let fixture = try await makeFixture()
    let mail = fixture.mail
    let coordinator = fixture.coordinator
    let check = Task { try await mail.service.syncNow() }
    let entered = fixture.fetcher.entered
    try await withTestTimeout { await entered.wait() }

    do {
      _ = try await withTestTimeout { try await coordinator.beginErase(timeout: 0.3) }
      XCTFail("a mail sync still running at the deadline must make the erase throw busy")
    } catch CoordinatorEraseError.busy {
      // expected
    }
    let erasing = await coordinator.isErasing
    XCTAssertFalse(erasing, "a busy erase gives the coordinator's gate back")
    XCTAssertFalse(fixture.mail.workGate.isClosed, "a busy erase reopens the mail gate")

    await fixture.fetcher.release.open()
    _ = try await withTestTimeout { try await check.value }
    _ = try await withTestTimeout { try await mail.service.syncNow() }
  }

  // MARK: - Fixtures

  private func makeFixture(honoursCancellation: Bool = false) async throws -> EraseDrainFixture {
    let fixture = try EraseDrainFixture(honoursCancellation: honoursCancellation)
    try await fixture.wire()
    fixtures.append(fixture)
    return fixture
  }

  /// A cancelled scan ends with `CancellationError`. Any other outcome is a failure.
  private func scanEndsCancelled(_ scan: Task<SyncSummary, Error>) async throws {
    do {
      _ = try await withTestTimeout { try await scan.value }
      XCTFail("a cancelled backfill must end with CancellationError")
    } catch is CancellationError {
      // expected
    }
  }

  /// Polls until the gate is closed, so a test can rely on the erase being in place.
  private func waitUntilErasing(_ coordinator: AppSyncCoordinator) async throws {
    try await withTestTimeout {
      while !(await coordinator.isErasing) {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
    }
  }

  /// After the erase returns, nothing else writes: the log stops growing, and the
  /// mail keys the held work wrote are back to their erased values.
  private func assertNothingWritesAfterErase(_ fixture: EraseDrainFixture) async throws {
    let settled = fixture.log.events
    try await Task.sleep(nanoseconds: 200_000_000)
    XCTAssertEqual(fixture.log.events, settled, "something wrote after the erase returned")
    XCTAssertFalse(
      fixture.preferences.bool(forKey: PreferenceKey.mailBackfillUnfinished),
      "the unfinished marker was written after the erase")
    XCTAssertNil(
      fixture.preferences.data(forKey: PreferenceKey.mailSyncCursor),
      "the sync cursor was written after the erase")
    XCTAssertNil(
      fixture.preferences.data(forKey: PreferenceKey.mailLastSyncAt),
      "the last-sync marker was written after the erase")
  }
}

// MARK: - Event names

/// The names the spies and the delete seam record under. Plain constants, so the
/// nonisolated doubles can read them.
private enum EraseDrainEvent {
  static let ingest = "ingest"
  static let searchReturned = "search.returned"
  static let delete = "erase.delete"
}

// MARK: - Fixture

/// Everything one test needs: a mail stack on the held fetcher, the coordinator,
/// and an eraser whose delete seam writes to the same log as the ingest spy. The
/// eraser runs on an in-memory store and a folder this test made, so no real
/// store or temporary file is touched.
@MainActor
private final class EraseDrainFixture {
  let log: EraseDrainLog
  let fetcher: EraseDrainFetcher
  let preferences = InMemoryKeyValueStore()
  let credentials = MemoryCredentialStore()
  let mail: MailStack
  let coordinator: AppSyncCoordinator
  private(set) var eraser: DataEraser!

  private let stack: InMemoryStack
  private let pipeline: IngestPipeline
  private let root: URL
  private let suiteName: String
  private let suite: UserDefaults

  init(honoursCancellation: Bool) throws {
    let log = EraseDrainLog()
    self.log = log
    fetcher = EraseDrainFetcher(log: log, honoursCancellation: honoursCancellation)
    stack = try InMemoryStack()
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("EraseDrainsMailWork-\(UUID().uuidString)", isDirectory: true)
    suiteName = "EraseDrainsMailWork.\(UUID().uuidString)"
    suite = UserDefaults(suiteName: suiteName)!

    mail = MailStack(
      fetcher: fetcher,
      pipeline: EraseDrainIngest(log: log),
      credentials: credentials,
      preferences: preferences
    )
    pipeline = IngestPipeline(store: EmptyPipelineStore())
    coordinator = AppSyncCoordinator(
      mail: mail,
      pipeline: pipeline,
      submitter: EraseDrainSubmitter()
    )
  }

  /// `MailStack` is an actor, so its service is read with `await`. The mailbox is
  /// connected first, as it is in the app before any Check now can be pressed.
  func wire() async throws {
    try await mail.service.connect(.test)
    let service = await mail.service
    let log = self.log
    eraser = DataEraser(
      container: stack.container,
      storageMode: { .cloudKit },
      sync: coordinator,
      pipeline: pipeline,
      mail: service,
      credentials: credentials,
      notifications: NoopNotificationScheduler(),
      preferences: preferences,
      standardDefaults: suite,
      firstRun: FirstRunGate(store: preferences),
      writes: WriteCoordinator(cache: InsightsCache()),
      storeDirectory: root.appendingPathComponent("store", isDirectory: true),
      tempDirectory: root.appendingPathComponent("temp", isDirectory: true),
      disconnectTimeout: 5,
      deleteRows: { _, _ in log.record(EraseDrainEvent.delete) },
      dropCaches: {}
    )
  }

  func cleanUp() {
    try? FileManager.default.removeItem(at: root)
    suite.removePersistentDomain(forName: suiteName)
  }
}

/// The order of the writes under test, appended from the spies and the delete
/// seam. A lock, not an actor, because the spies are called from a nonisolated
/// context and the test reads the log synchronously.
private final class EraseDrainLog: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []

  func record(_ event: String) {
    lock.lock()
    recorded.append(event)
    lock.unlock()
  }

  var events: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func index(of event: String) -> Int? {
    events.firstIndex(of: event)
  }

  func count(of event: String) -> Int {
    events.filter { $0 == event }.count
  }
}

/// Stands in for the transaction pipeline: records each batch it is handed.
private struct EraseDrainIngest: DraftIngesting {
  let log: EraseDrainLog

  func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    log.record(EraseDrainEvent.ingest)
    return .empty
  }
}

/// Holds the first search until the test releases it. By default the hold ignores
/// cancellation, so only the release ends it. With `honoursCancellation`, the hold
/// is a sleep that a cancel ends at once, which is how a real socket read behaves.
/// Once a search returns, it records that in the log, before anything else runs.
/// The search then finds one message: a bank debit that the extractor turns into a
/// draft, if the scan is still running to fetch it.
private final class EraseDrainFetcher: MailFetching, @unchecked Sendable {
  /// Opened when the first search is reached, so a test can wait for the hold.
  let entered = StartSignal()
  /// Opened by the test, to let a held search that ignores cancellation finish.
  let release = StartSignal()

  private let log: EraseDrainLog
  private let honoursCancellation: Bool
  private let lock = NSLock()
  private var searches = 0

  init(log: EraseDrainLog, honoursCancellation: Bool) {
    self.log = log
    self.honoursCancellation = honoursCancellation
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}

  func selectMailbox(_ name: String) async throws -> MailboxState {
    MailboxState(name: name, uidValidity: 7, uidNext: 2)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    try await search()
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    try await search()
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    try await search()
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    guard uids.contains(1) else { return [] }
    return [try Self.sbiDebit()]
  }

  /// Only the first search is held. Later windows find nothing, so the one
  /// message is found once and fetched once.
  private func search() async throws -> [UInt32] {
    guard takeFirstSearch() else { return [] }
    await entered.open()
    defer { log.record(EraseDrainEvent.searchReturned) }
    if honoursCancellation {
      // Throws `CancellationError` as soon as the caller cancels, like a socket read.
      try await Task.sleep(nanoseconds: 10_000_000_000)
    } else {
      await release.wait()
    }
    return [1]
  }

  private func takeFirstSearch() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    searches += 1
    return searches == 1
  }

  /// A real SBI debit alert from the NomiIngest fixtures, read by path the way
  /// `AccountBindingTests` reads its fixture.
  private static func sbiDebit() throws -> MailMessage {
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent(
      "NomiIngest/Tests/NomiIngestTests/Fixtures/Mail/sbi_debit_upi.eml")
    return try RFC822Message.parse(try Data(contentsOf: url), uid: 1, uidValidity: 7)
  }
}

/// Records the background requests the erase cancels. The test does not inspect them.
private final class EraseDrainSubmitter: BackgroundTaskSubmitting, @unchecked Sendable {
  func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval) {}
  func cancelAll() {}
}
