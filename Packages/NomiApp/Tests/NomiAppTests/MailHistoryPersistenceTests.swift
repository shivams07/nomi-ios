import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// FU-3 (MH): "ever connected" and "last sync" survive a relaunch, and are
/// exposed as `MailConnectionService.history` on the screen-facing service.
///
/// Each "relaunch" is a second `MailStack` built over the same
/// `InMemoryKeyValueStore` instance, with nothing else carried across. Whatever
/// the second stack reports came from the store.
///
/// The doubles (`MemoryCredentialStore`, `SilentPipeline`, `RecordingMailFetcher`,
/// `IMAPCredentials.test`) are the ones `MailCursorPersistenceTests` already
/// defines in this target, so nothing here is a second copy of them.
/// Fixed clocks for the injected `now`. File scope so that the `@Sendable`
/// closures do not capture the test case.
private let historyClockOne = Date(timeIntervalSince1970: 1_787_000_000)
private let historyClockTwo = Date(timeIntervalSince1970: 1_787_259_200)  // three days later

final class MailHistoryPersistenceTests: XCTestCase {

  // MARK: - Ever connected

  func testAFreshInstallHasNeverConnectedAndNeverSynced() async {
    let stack = makeHistoryStack(preferences: InMemoryKeyValueStore())

    let history = await stack.service.history

    XCTAssertEqual(history, .never)
  }

  /// Item 6. A connect on one launch is still known on the next, through the
  /// screen-facing service and not just the wrapper underneath it.
  func testASuccessfulConnectIsKnownToALaterLaunch() async throws {
    let preferences = InMemoryKeyValueStore()
    let first = makeHistoryStack(preferences: preferences)

    try await first.service.connect(.test)

    let relaunched = makeHistoryStack(preferences: preferences)
    let history = await relaunched.service.history
    XCTAssertTrue(history.hasEverConnected)
    XCTAssertNil(history.lastSync, "connecting alone is not a sync")
  }

  /// A connect that fails has not connected, so it must not set the flag.
  func testAFailedConnectIsNotCountedAsConnected() async throws {
    let store = MemoryCredentialStore()
    let preferences = InMemoryKeyValueStore()
    let stack = MailStack(
      fetcher: ServerDownFetcher(inner: RecordingMailFetcher(uids: [1])),
      pipeline: SilentPipeline(),
      credentials: store,
      preferences: preferences
    )

    try? await stack.service.connect(.test)

    let history = await stack.service.history
    XCTAssertFalse(history.hasEverConnected)
  }

  // MARK: - Disconnect is history, not status

  /// Item 7. Disconnecting turns collection off. It does not make the earlier
  /// connection or the earlier sync untrue, so both survive it and a relaunch.
  func testDisconnectLeavesBothValuesAsTheyWere() async throws {
    let preferences = InMemoryKeyValueStore()
    let stack = makeHistoryStack(
      fetcher: RecordingMailFetcher(uids: [1, 2]),
      preferences: preferences,
      now: { historyClockOne }
    )

    try await stack.service.connect(.test)
    _ = try await stack.service.syncNow()
    try await stack.service.disconnect()

    let inProcess = await stack.service.history
    XCTAssertEqual(inProcess, MailConnectionHistory(hasEverConnected: true, lastSync: historyClockOne))

    let relaunched = makeHistoryStack(preferences: preferences)
    let afterRelaunch = await relaunched.service.history
    XCTAssertEqual(afterRelaunch, MailConnectionHistory(hasEverConnected: true, lastSync: historyClockOne))
  }

  // MARK: - Last sync

  /// Item 8, the sync half. The value is the injected clock, and it survives a
  /// relaunch.
  func testASuccessfulSyncRecordsTheInjectedClockAcrossALaunch() async throws {
    let preferences = InMemoryKeyValueStore()
    let stack = makeHistoryStack(
      fetcher: RecordingMailFetcher(uids: [1, 2]),
      preferences: preferences,
      now: { historyClockOne }
    )

    try await stack.service.connect(.test)
    _ = try await stack.service.syncNow()

    let relaunched = makeHistoryStack(preferences: preferences)
    let history = await relaunched.service.history
    XCTAssertEqual(history.lastSync, historyClockOne)
  }

  /// Item 8, the backfill half. A backfill is a sync too.
  func testASuccessfulBackfillRecordsTheInjectedClockAcrossALaunch() async throws {
    let preferences = InMemoryKeyValueStore()
    let stack = makeHistoryStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3]),
      preferences: preferences,
      now: { historyClockOne }
    )

    try await stack.service.connect(.test)
    try await stack.service.startBackfill(months: 6)

    let relaunched = makeHistoryStack(preferences: preferences)
    let history = await relaunched.service.history
    XCTAssertEqual(history.lastSync, historyClockOne)
  }

  /// Item 8, the failure half. "Last synced" means the last time a sync worked.
  /// A later failed sync must not move it forward to the time it failed.
  func testAFailedSyncKeepsTheEarlierLastSync() async throws {
    let preferences = InMemoryKeyValueStore()
    let first = makeHistoryStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3]),
      preferences: preferences,
      now: { historyClockOne }
    )
    try await first.service.connect(.test)
    _ = try await first.service.syncNow()

    // The next launch finds a new message, and fetching it fails.
    let second = makeHistoryStack(
      fetcher: RecordingMailFetcher(uids: [1, 2, 3, 4], failFetchAfterBatches: 0),
      preferences: preferences,
      now: { historyClockTwo }
    )
    try await second.service.connect(.test)
    do {
      _ = try await second.service.syncNow()
      XCTFail("the fetch was supposed to fail, or the test proves nothing")
    } catch {
      // Expected.
    }

    let history = await second.service.history
    XCTAssertEqual(history.lastSync, historyClockOne)
  }

  // MARK: - The launch-time reconnect (FU-3's data-loss fix, end to end)

  /// `reconnectFromKeychain` runs at every launch. With the server down, its
  /// connect fails, and the saved password must still be there for the next
  /// launch to try again. Before the `IMAPMailConnectionService.connect` fix
  /// this read back nil.
  func testAFailedLaunchReconnectKeepsTheStoredPassword() async throws {
    let store = MemoryCredentialStore()
    try store.save(.test)
    let stack = MailStack(
      fetcher: ServerDownFetcher(inner: RecordingMailFetcher(uids: [1])),
      pipeline: SilentPipeline(),
      credentials: store,
      preferences: InMemoryKeyValueStore()
    )

    await stack.reconnectFromKeychain(store)

    let kept = try store.load()
    XCTAssertEqual(kept?.password, IMAPCredentials.test.password)
    XCTAssertEqual(kept?.address, IMAPCredentials.test.address)
  }

  // MARK: - The contract default

  /// The default that lets every existing conformer and fake stay as it is.
  func testAConformerThatKeepsNoHistoryReportsNever() {
    XCTAssertEqual(NoHistoryService().history, .never)
  }

  /// Six keys in one store. A collision would make history read somebody
  /// else's value, and nothing else would fail.
  func testTheHistoryKeysDoNotCollideWithAnyOtherKey() {
    let keys = [
      PreferenceKey.hasCompletedFirstRun,
      PreferenceKey.notificationSettings,
      PreferenceKey.mailSyncCursor,
      PreferenceKey.mailBackfillUnfinished,
      PreferenceKey.mailHasConnected,
      PreferenceKey.mailLastSyncAt,
    ]
    XCTAssertEqual(Set(keys).count, keys.count)
  }

  // MARK: -

  private func makeHistoryStack(
    fetcher: any MailFetching = RecordingMailFetcher(uids: []),
    preferences: InMemoryKeyValueStore,
    credentials: MemoryCredentialStore = MemoryCredentialStore(),
    now: @escaping @Sendable () -> Date = { historyClockOne }
  ) -> MailStack {
    MailStack(
      fetcher: fetcher,
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: preferences,
      now: now
    )
  }
}

// MARK: - Doubles

/// A fetcher whose server is unreachable: every connect fails with a transport
/// error that says nothing about the password. Everything else is the real
/// `RecordingMailFetcher`.
private struct ServerDownFetcher: MailFetching {
  let inner: RecordingMailFetcher

  func connect(_ credentials: IMAPCredentials) async throws {
    throw IMAPTransportError.connectionClosed
  }

  func disconnect() async throws { try await inner.disconnect() }

  func selectMailbox(_ name: String) async throws -> MailboxState {
    try await inner.selectMailbox(name)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    try await inner.uids(since: date, in: mailbox)
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    try await inner.uids(since: since, before: before, in: mailbox)
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    try await inner.uids(after: uid, in: mailbox)
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    try await inner.fetch(uids: uids, in: mailbox)
  }
}

/// A connection service that predates `history`. It declares nothing about
/// history, so it must inherit the protocol default.
private final class NoHistoryService: MailConnectionService, @unchecked Sendable {
  let state = AsyncStream<MailConnectionState> { $0.finish() }
  let backfillProgress = AsyncStream<BackfillProgress> { $0.finish() }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}

  func syncNow() async throws -> SyncSummary {
    SyncSummary(
      scanned: 0, created: 0, merged: 0, flagged: 0,
      packMatched: 0, heuristicMatched: 0, unmatchedSenders: [])
  }

  func startBackfill(months: Int) async throws -> SyncSummary {
    SyncSummary(
      scanned: 0, created: 0, merged: 0, flagged: 0,
      packMatched: 0, heuristicMatched: 0, unmatchedSenders: [])
  }
}
