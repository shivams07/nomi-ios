import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// Finding 6: the cursor was persisted on one route into a sync and not on the
/// one every screen actually uses.
///
/// **The assertions here go through `MailStack.service`, deliberately.** That is
/// what `AppEnvironment.mailConnectionService` returns and what `SettingsScreen`,
/// `ConnectMailScreen` and `BackfillScreen` hold. A test written against
/// `MailStack.syncNow()` — the method that always did persist — would have
/// passed on every commit while the bug was live, which is precisely why the bug
/// was live.
///
/// Nothing here is stubbed above the transport: the real `MailSyncEngine`, the
/// real `IMAPMailConnectionService` and the real `BroadcastingMailConnectionService`
/// are all in the path. Only `MailFetching` is faked, which is the seam U2
/// defines for exactly this.
final class MailCursorPersistenceTests: XCTestCase {

  // MARK: - The screen-facing route

  /// The regression. Before §D1 this stored nothing at all: `service` was the
  /// broadcaster over the raw `IMAPMailConnectionService`, and the persisting
  /// wrapper sat beside it on `MailStack` where no screen could reach it.
  func testASyncThroughTheScreenFacingServicePersistsTheCursor() async throws {
    let preferences = InMemoryKeyValueStore()
    let fetcher = RecordingMailFetcher(uids: [11, 12, 42])
    let stack = makeStack(fetcher: fetcher, preferences: preferences)

    try await stack.service.connect(.test)
    _ = try await stack.service.syncNow()

    let cursor = try XCTUnwrap(persistedCursor(in: preferences))
    XCTAssertEqual(cursor.mailbox, "INBOX")
    XCTAssertEqual(cursor.uidValidity, RecordingMailFetcher.defaultUIDValidity)
    XCTAssertEqual(cursor.lastSeenUID, 42)
  }

  /// The route `AppSyncCoordinator` takes. It has to land on the same value as
  /// the screen route, or the two are still separate doors with the old bug
  /// hiding between them.
  func testTheCoordinatorRouteLandsOnTheSameCursor() async throws {
    let preferences = InMemoryKeyValueStore()
    let fetcher = RecordingMailFetcher(uids: [11, 12, 42])
    let stack = makeStack(fetcher: fetcher, preferences: preferences)

    try await stack.service.connect(.test)
    _ = try await stack.syncNow()

    let cursor = try XCTUnwrap(persistedCursor(in: preferences))
    XCTAssertEqual(cursor.lastSeenUID, 42)
  }

  /// A cursor written *before* the call returns, not by a detached task that
  /// runs at some later moment.
  ///
  /// This is the assertion the old `defer { Task { await persistCursor() } }`
  /// could not support: it could only be tested by sleeping and hoping, which is
  /// the same thing as not testing it.
  func testTheCursorIsOnDiskByTheTimeSyncNowReturns() async throws {
    let preferences = InMemoryKeyValueStore()
    let stack = makeStack(fetcher: RecordingMailFetcher(uids: [7]), preferences: preferences)

    try await stack.service.connect(.test)
    _ = try await stack.service.syncNow()

    XCTAssertNotNil(preferences.data(forKey: PreferenceKey.mailSyncCursor))
  }

  /// §2.17's completed-prefix rule. A sync that throws part-way still moved the
  /// cursor as far as the last batch it finished, and throwing that away would
  /// re-fetch every completed batch on the next run.
  func testAFailedSyncStillPersistsTheCompletedPrefix() async throws {
    let preferences = InMemoryKeyValueStore()
    // 60 UIDs is two batches at `MailSyncEngine.fetchBatchSize` of 50. The
    // second one is the one that dies.
    let fetcher = RecordingMailFetcher(
      uids: Array<UInt32>(1...60),
      failFetchAfterBatches: 1
    )
    let stack = makeStack(fetcher: fetcher, preferences: preferences)

    try await stack.service.connect(.test)
    do {
      _ = try await stack.service.syncNow()
      XCTFail("the second batch was supposed to throw")
    } catch {
      // Expected — the assertion is about what survived it.
    }

    let cursor = try XCTUnwrap(persistedCursor(in: preferences))
    XCTAssertEqual(cursor.lastSeenUID, 50)
  }

  /// A cursor already on disk is read back at construction, so a second launch
  /// resumes rather than rescanning. Asserted through the fetcher: an
  /// incremental sync asks `uids(after:)`, a cold one asks `uids(since:)`.
  func testAStoredCursorMakesTheNextSyncIncremental() async throws {
    let preferences = InMemoryKeyValueStore()
    try seed(
      cursor: MailSyncCursor(
        mailbox: "INBOX",
        uidValidity: RecordingMailFetcher.defaultUIDValidity,
        lastSeenUID: 20
      ),
      into: preferences
    )
    let fetcher = RecordingMailFetcher(uids: [11, 12, 42])
    let stack = makeStack(fetcher: fetcher, preferences: preferences)

    try await stack.service.connect(.test)
    _ = try await stack.service.syncNow()

    XCTAssertEqual(fetcher.calls.incrementalSearches, 1)
    XCTAssertEqual(fetcher.calls.fullRescans, 0)
    // Only UID 42 was above the cursor, so that is where it ends up.
    let cursor = try XCTUnwrap(persistedCursor(in: preferences))
    XCTAssertEqual(cursor.lastSeenUID, 42)
  }

  // MARK: - Unfinished backfills

  func testAFreshStackHasNoUnfinishedBackfill() async {
    let stack = makeStack(fetcher: RecordingMailFetcher(uids: []))
    let unfinished = await stack.backfillIsUnfinished
    XCTAssertFalse(unfinished)
  }

  func testABackfillThatCompletesLeavesNothingUnfinished() async throws {
    let stack = makeStack(fetcher: RecordingMailFetcher(uids: [1, 2, 3]))

    try await stack.service.connect(.test)
    try await stack.service.startBackfill(months: 6)

    let unfinished = await stack.backfillIsUnfinished
    XCTAssertFalse(unfinished)
  }

  /// The case that has to be visible for `AppSyncCoordinator` to ask iOS for the
  /// processing task. Cancelling the `Task` is what `BackfillScreen` does, and —
  /// until unit C lands — what merely leaving the screen does too.
  func testAnInterruptedBackfillIsRecordedAsUnfinished() async throws {
    let searchStarted = StartSignal()
    let fetcher = RecordingMailFetcher(uids: [1, 2, 3], blockOnSearch: searchStarted)
    let stack = makeStack(fetcher: fetcher)

    try await stack.service.connect(.test)
    let backfill = Task { try? await stack.service.startBackfill(months: 6) }
    await searchStarted.wait()
    backfill.cancel()
    _ = await backfill.value

    let unfinished = await stack.backfillIsUnfinished
    XCTAssertTrue(unfinished)
  }

  /// `startBackfill` on a mailbox that was never connected throws before it does
  /// anything. Recording that as "unfinished" would ask iOS for a background
  /// task, once per backgrounding, that can only fail the same way.
  func testABackfillOnADisconnectedMailboxIsNotRecordedAsUnfinished() async {
    let stack = makeStack(fetcher: RecordingMailFetcher(uids: [1]))

    do {
      try await stack.service.startBackfill(months: 6)
      XCTFail("a disconnected mailbox was supposed to throw")
    } catch {
      XCTAssertEqual(error as? IMAPTransportError, .notConnected)
    }

    let unfinished = await stack.backfillIsUnfinished
    XCTAssertFalse(unfinished)
  }

  /// What persisting the marker buys, and the only thing it buys: the in-memory
  /// version read `false` here, so a scan the OS interrupted by killing the
  /// process was never finished by anything.
  func testAnUnfinishedBackfillSurvivesIntoTheNextLaunch() async throws {
    let preferences = InMemoryKeyValueStore()
    let searchStarted = StartSignal()
    let stack = makeStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3], blockOnSearch: searchStarted),
      preferences: preferences
    )

    try await stack.service.connect(.test)
    let backfill = Task { try? await stack.service.startBackfill(months: 6) }
    await searchStarted.wait()
    backfill.cancel()
    _ = await backfill.value

    // A relaunch: same preferences, everything above them built from scratch.
    let relaunched = makeStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3]),
      preferences: preferences
    )

    let unfinished = await relaunched.backfillIsUnfinished
    XCTAssertTrue(unfinished)
  }

  /// Disconnecting is the user turning collection off. Continuing to ask iOS to
  /// finish a scan of the mailbox they just disconnected would be asking for the
  /// one thing they said no to.
  func testDisconnectingClearsTheUnfinishedMarker() async throws {
    let searchStarted = StartSignal()
    let stack = makeStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3], blockOnSearch: searchStarted))

    try await stack.service.connect(.test)
    let backfill = Task { try? await stack.service.startBackfill(months: 6) }
    await searchStarted.wait()
    backfill.cancel()
    _ = await backfill.value

    let interrupted = await stack.backfillIsUnfinished
    XCTAssertTrue(interrupted, "precondition")

    try await stack.service.disconnect()

    let afterDisconnect = await stack.backfillIsUnfinished
    XCTAssertFalse(afterDisconnect)
  }

  /// A backfill attempted before the Keychain reconnect has happened throws
  /// `notConnected` without starting anything. It must leave an *earlier*
  /// launch's unfinished scan alone: clearing it here would mean the background
  /// task that arrives first on a cold launch forgets the scan permanently.
  func testAFailedAttemptDoesNotForgetAnEarlierUnfinishedBackfill() async {
    let preferences = InMemoryKeyValueStore()
    preferences.set(true, forKey: PreferenceKey.mailBackfillUnfinished)
    let stack = makeStack(fetcher: RecordingMailFetcher(uids: [1]), preferences: preferences)

    do {
      try await stack.service.startBackfill(months: 6)
      XCTFail("a disconnected mailbox was supposed to throw")
    } catch {
      XCTAssertEqual(error as? IMAPTransportError, .notConnected)
    }

    let unfinished = await stack.backfillIsUnfinished
    XCTAssertTrue(unfinished)
  }

  // MARK: -

  private func persistedCursor(in preferences: InMemoryKeyValueStore) throws -> MailSyncCursor? {
    guard let data = preferences.data(forKey: PreferenceKey.mailSyncCursor) else { return nil }
    return try JSONDecoder().decode(MailSyncCursor.self, from: data)
  }

  private func seed(cursor: MailSyncCursor, into preferences: InMemoryKeyValueStore) throws {
    preferences.set(try JSONEncoder().encode(cursor), forKey: PreferenceKey.mailSyncCursor)
  }
}

// MARK: - Doubles
//
// Shared with `BackgroundWorkRoutingTests`, which builds the same stack and
// hands it to an `AppSyncCoordinator`. They live here rather than in a third
// file because the fix-scope design names test files individually and adding one
// it does not name is an overlap with whatever unit adds it next.

func makeStack(
  fetcher: any MailFetching,
  preferences: InMemoryKeyValueStore = InMemoryKeyValueStore()
) -> MailStack {
  MailStack(
    fetcher: fetcher,
    pipeline: SilentPipeline(),
    credentials: MemoryCredentialStore(),
    preferences: preferences
  )
}

extension IMAPCredentials {
  static let test = IMAPCredentials(
    host: "imap.example.com", port: 993, address: "someone@example.com", password: "app-password"
  )
}

/// Never reached by these tests — `RecordingMailFetcher.fetch` returns no
/// messages, so the engine classifies nothing and has no drafts to hand over.
/// It exists because `MailStack` requires one.
struct SilentPipeline: DraftIngesting {
  func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult { .empty }
}

final class MemoryCredentialStore: MailCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: IMAPCredentials?

  func save(_ credentials: IMAPCredentials) throws {
    lock.lock()
    stored = credentials
    lock.unlock()
  }

  func load() throws -> IMAPCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func delete() throws {
    lock.lock()
    stored = nil
    lock.unlock()
  }
}

/// The transport seam, recording which *kind* of search it was asked for.
///
/// That distinction is the whole point: `uids(after:)` is an incremental sync,
/// `uids(since:before:)` is a backfill window, and telling a `.backfill`
/// background task from a `.refresh` one is a question about which of those two
/// the fetcher saw.
final class RecordingMailFetcher: MailFetching, @unchecked Sendable {
  static let defaultUIDValidity: UInt32 = 7

  struct Calls: Equatable {
    var fullRescans = 0
    var backfillWindows = 0
    var incrementalSearches = 0
    var fetches = 0
  }

  private let lock = NSLock()
  private let availableUIDs: [UInt32]
  private let uidValidity: UInt32
  private let blockOnSearch: StartSignal?
  private let failFetchAfterBatches: Int?
  private var recorded = Calls()
  private var cancellationSeen = false

  init(
    uids: [UInt32],
    uidValidity: UInt32 = RecordingMailFetcher.defaultUIDValidity,
    blockOnSearch: StartSignal? = nil,
    failFetchAfterBatches: Int? = nil
  ) {
    self.availableUIDs = uids
    self.uidValidity = uidValidity
    self.blockOnSearch = blockOnSearch
    self.failFetchAfterBatches = failFetchAfterBatches
  }

  var calls: Calls {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  /// Whether a search was still waiting when the task was cancelled. The
  /// expiration test asserts on it: an expiration handler that cancels nothing
  /// is exactly the bug being fixed, and "the run finished" alone cannot tell
  /// the two apart.
  var sawCancellation: Bool {
    lock.lock()
    defer { lock.unlock() }
    return cancellationSeen
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}

  func selectMailbox(_ name: String) async throws -> MailboxState {
    MailboxState(name: name, uidValidity: uidValidity, uidNext: (availableUIDs.max() ?? 0) + 1)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    record { $0.fullRescans += 1 }
    try await blockIfAsked()
    return availableUIDs
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    record { $0.backfillWindows += 1 }
    try await blockIfAsked()
    // Every window returns the same set; the engine unions and sorts them, so
    // the result is the same as one window returning them once.
    return availableUIDs
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    record { $0.incrementalSearches += 1 }
    try await blockIfAsked()
    return availableUIDs.filter { $0 > uid }
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    // Through a synchronous helper for the same reason as `noteCancellation`
    // below: an `NSLock` taken directly in an async function is a warning today
    // and an error under the Swift 6 language mode.
    let index = countFetch()

    if let failFetchAfterBatches, index > failFetchAfterBatches {
      throw IMAPTransportError.serverClosedMidCommand(tag: "A1", text: "BYE")
    }
    // No messages. The engine still advances the cursor to the end of a batch it
    // fetched, which is the property under test; classification and ingest have
    // their own tests in NomiIngest and are not re-run here.
    return []
  }

  /// Opens the gate — "a search is in flight, cancel me now" — and then waits
  /// long enough that only cancellation ends it. Five seconds rather than
  /// minutes so a broken cancellation fails the test instead of hanging CI.
  private func blockIfAsked() async throws {
    guard let blockOnSearch else { return }
    await blockOnSearch.open()
    do {
      try await Task.sleep(nanoseconds: 5_000_000_000)
    } catch {
      // Through a synchronous helper, not `lock.lock()` inline: taking an
      // `NSLock` directly in an async function is a warning today and an error
      // under the Swift 6 language mode. Nothing suspends inside the helper.
      noteCancellation()
      throw error
    }
  }

  private func countFetch() -> Int {
    lock.lock()
    defer { lock.unlock() }
    recorded.fetches += 1
    return recorded.fetches
  }

  private func noteCancellation() {
    lock.lock()
    cancellationSeen = true
    lock.unlock()
  }

  private func record(_ mutate: (inout Calls) -> Void) {
    lock.lock()
    mutate(&recorded)
    lock.unlock()
  }
}

/// A one-shot "it has started" signal, so the tests that need to interrupt work
/// mid-flight can do it at a defined moment instead of after a sleep.
actor StartSignal {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open() {
    guard !isOpen else { return }
    isOpen = true
    let waiting = waiters
    waiters = []
    waiting.forEach { $0.resume() }
  }

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waiters.append(continuation)
    }
  }
}
