import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// R5a: the persisted cursor advances after every completed batch, not only at
/// the end of a sync (X6), through the real `MailStack`.
///
/// Built on `makeStack`, `RecordingMailFetcher` and `InMemoryKeyValueStore` from
/// `MailCursorPersistenceTests`, which this file does not edit.
final class MailCursorBatchPersistenceTests: XCTestCase {

  /// Three batches of 50, 50 and 20. The third fetch throws.
  ///
  /// The assertion is taken **inside the third fetch**, so it reads what is on
  /// disk while the sync is still running. A check made after the throw could
  /// not tell a per-batch write from the end-of-sync write that
  /// `CursorPersistingMailConnectionService` does regardless.
  func testTheCursorIsOnDiskBeforeTheNextBatchIsFetched() async throws {
    let preferences = InMemoryKeyValueStore()
    let probe = PersistedCursorProbe(
      inner: RecordingMailFetcher(
        uids: Array<UInt32>(1...120),
        failFetchAfterBatches: 2
      ),
      preferences: preferences
    )
    let stack = makeStack(fetcher: probe, preferences: preferences)

    try await stack.service.connect(.test)
    do {
      _ = try await stack.service.syncNow()
      XCTFail("the third batch was supposed to throw")
    } catch {
      // Expected. The assertions are about what was on disk along the way.
    }

    // Nothing before the first batch; the end of batch one (50) before the
    // second fetch; the end of batch two (100) before the third. The fourth
    // fetch is the one retry `reconnectingOnce` makes after a
    // `serverClosedMidCommand`, which reruns the sync from the persisted 100.
    XCTAssertEqual(probe.lastSeenUIDAtEachFetch, [nil, 50, 100, 100])
    XCTAssertEqual(try persistedCursor(in: preferences)?.lastSeenUID, 100)
  }

  /// What the per-batch write is for: the next launch resumes from the end of
  /// the last completed batch, so the 100 already fetched is not fetched again.
  func testARelaunchResumesFromTheLastCompletedBatch() async throws {
    let preferences = InMemoryKeyValueStore()
    let failing = makeStack(
      fetcher: RecordingMailFetcher(uids: Array<UInt32>(1...120), failFetchAfterBatches: 2),
      preferences: preferences
    )
    try await failing.service.connect(.test)
    do {
      _ = try await failing.service.syncNow()
      XCTFail("the third batch was supposed to throw")
    } catch {
      // Expected. The run that follows is the one under test.
    }

    let fetcher = RecordingMailFetcher(uids: Array<UInt32>(1...120))
    let relaunched = makeStack(fetcher: fetcher, preferences: preferences)
    try await relaunched.service.connect(.test)
    _ = try await relaunched.service.syncNow()

    XCTAssertEqual(fetcher.calls.incrementalSearches, 1)
    XCTAssertEqual(fetcher.calls.fullRescans, 0)
    XCTAssertEqual(try persistedCursor(in: preferences)?.lastSeenUID, 120)
  }

  // MARK: -

  private func persistedCursor(in preferences: InMemoryKeyValueStore) throws -> MailSyncCursor? {
    guard let data = preferences.data(forKey: PreferenceKey.mailSyncCursor) else { return nil }
    return try JSONDecoder().decode(MailSyncCursor.self, from: data)
  }
}

/// Delegates every call to `RecordingMailFetcher`, and at each `fetch` records
/// what the preferences store holds at that moment.
///
/// It records **before** delegating, so the value seen by fetch *n* is what
/// batch *n-1* left on disk.
private final class PersistedCursorProbe: MailFetching, @unchecked Sendable {
  private let inner: RecordingMailFetcher
  private let preferences: InMemoryKeyValueStore
  private let lock = NSLock()
  private var seen: [UInt32?] = []

  init(inner: RecordingMailFetcher, preferences: InMemoryKeyValueStore) {
    self.inner = inner
    self.preferences = preferences
  }

  var lastSeenUIDAtEachFetch: [UInt32?] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    try await inner.connect(credentials)
  }

  func disconnect() async throws {
    try await inner.disconnect()
  }

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
    recordPersistedCursor()
    return try await inner.fetch(uids: uids, in: mailbox)
  }

  // Synchronous so the lock is never taken inside an async function.
  private func recordPersistedCursor() {
    let data = preferences.data(forKey: PreferenceKey.mailSyncCursor)
    let cursor = data.flatMap { try? JSONDecoder().decode(MailSyncCursor.self, from: $0) }
    lock.lock()
    seen.append(cursor?.lastSeenUID)
    lock.unlock()
  }
}
