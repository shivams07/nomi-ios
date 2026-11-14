import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// R5a: the cursor's UIDVALIDITY rule, the per-batch cursor sink, cancellation
/// at batch boundaries, and the connection service's cancelled-state rule.
///
/// Reuses `StubFetcher`, `BatchingFetcher` and `RecordingPipeline` from
/// `MailSyncEngineTests`. `IMAPMailConnectionServiceTests` keeps its doubles
/// private, so the service section declares its own below.
final class MailSyncCursorTests: XCTestCase {

  private func message(_ file: String, uid: UInt32) throws -> MailMessage {
    try MailFixtures.message(file, uid: uid)
  }

  private func mailbox(validity: UInt32) -> MailboxState {
    MailboxState(name: "INBOX", uidValidity: validity, uidNext: 999)
  }

  // MARK: - UIDVALIDITY (X4)

  func testValidityChangeRestartsTheCursorAtZero() async throws {
    let fetcher = StubFetcher(
      messages: [
        try message("hdfc_debit_netbanking.eml", uid: 3),
        try message("kotak_debit_card.eml", uid: 4),
      ],
      state: mailbox(validity: 200)
    )
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 100, lastSeenUID: 5000)
    )

    _ = try await engine.syncNow()

    let cursor = await engine.cursor
    XCTAssertEqual(cursor, MailSyncCursor(mailbox: "INBOX", uidValidity: 200, lastSeenUID: 4))
  }

  func testValidityChangeWithNoMailStillAdoptsTheNewValidity() async throws {
    let sink = CursorSink()
    let engine = MailSyncEngine(
      fetcher: StubFetcher(messages: [], state: mailbox(validity: 200)),
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 100, lastSeenUID: 5000),
      onCursorAdvanced: sink.callback
    )

    _ = try await engine.syncNow()

    let expected = MailSyncCursor(mailbox: "INBOX", uidValidity: 200, lastSeenUID: 0)
    let cursor = await engine.cursor
    XCTAssertEqual(cursor, expected)
    XCTAssertEqual(sink.recorded, [expected], "the empty-run assignment reaches the sink too")
  }

  func testSameValidityKeepsTheHigherUID() async throws {
    let engine = MailSyncEngine(
      fetcher: StubFetcher(
        messages: [try message("hdfc_debit_netbanking.eml", uid: 10)],
        state: mailbox(validity: 100)
      ),
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 100, lastSeenUID: 50)
    )

    _ = try await engine.backfill(months: 6)

    let cursor = await engine.cursor
    XCTAssertEqual(cursor?.lastSeenUID, 50, "a backfill below the cursor must not move it back")
  }

  // MARK: - Per-batch cursor (X6)

  func testEveryCompletedBatchReachesTheSink() async throws {
    let sink = CursorSink()
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(
        uids: Array<UInt32>(1...120),
        template: try message("hdfc_debit_netbanking.eml", uid: 1)
      ),
      pipeline: RecordingPipeline(),
      onCursorAdvanced: sink.callback
    )

    _ = try await engine.syncNow()

    XCTAssertEqual(sink.recorded.map(\.lastSeenUID), [50, 100, 120])
  }

  func testAFailingBatchDoesNotReachTheSink() async throws {
    let sink = CursorSink()
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(
        uids: Array<UInt32>(1...120),
        template: try message("hdfc_debit_netbanking.eml", uid: 1),
        failOnFetchCall: 2
      ),
      pipeline: RecordingPipeline(),
      onCursorAdvanced: sink.callback
    )

    do {
      _ = try await engine.syncNow()
      XCTFail("the second batch was supposed to throw")
    } catch {
      // Expected. The assertion is about what the sink saw before it.
    }

    XCTAssertEqual(sink.recorded.map(\.lastSeenUID), [50])
  }

  // MARK: - Cancellation (X14, engine half)

  func testCancellationStopsAtTheNextBatch() async throws {
    let sink = CursorSink()
    let fetcher = CancelOnFirstFetch(
      uids: Array<UInt32>(1...120),
      template: try message("hdfc_debit_netbanking.eml", uid: 1)
    )
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      onCursorAdvanced: sink.callback
    )

    let backfill = Task { try await engine.backfill(months: 6) }
    do {
      _ = try await backfill.value
      XCTFail("a cancelled backfill was supposed to throw")
    } catch {
      XCTAssertTrue(error is CancellationError, "got \(error)")
    }

    XCTAssertEqual(fetcher.fetchCount, 1, "batch two must not be fetched")
    XCTAssertEqual(sink.recorded.map(\.lastSeenUID), [50], "batch one completed before the cancel")
  }

  // MARK: - Connection service (R5a step 5)

  /// A cancelled sync is not a failure: the state goes back to `.connected`
  /// and the stream never carries `.failed`.
  func testCancelledBackfillDoesNotYieldFailed() async throws {
    let fetcher = HoldInSearch()
    let service = makeService(fetcher: fetcher)
    var states = service.state.makeAsyncIterator()

    try await service.connect(CursorTestCredentials.credentials)
    let backfill = Task { try await service.startBackfill(months: 6) }
    await fetcher.waitUntilSearching()
    backfill.cancel()
    do {
      _ = try await backfill.value
      XCTFail("a cancelled backfill was supposed to throw")
    } catch {
      XCTAssertTrue(error is CancellationError, "got \(error)")
    }

    let connected = MailConnectionState.connected(
      address: CursorTestCredentials.credentials.address, lastSync: nil)
    var seen: [MailConnectionState] = []
    for _ in 0..<4 {
      if let next = await states.next() { seen.append(next) }
    }
    XCTAssertEqual(seen, [.disconnected, .connecting, connected, connected])
  }

  /// `reconnectingOnce` reloads and reconnects only when the socket is gone. A
  /// cancellation is not that, so the connect count must stay at the one the
  /// service made itself.
  func testCancelledSyncDoesNotReconnect() async throws {
    let fetcher = HoldInSearch()
    let service = makeService(fetcher: fetcher)
    var states = service.state.makeAsyncIterator()

    try await service.connect(CursorTestCredentials.credentials)
    let sync = Task { try await service.syncNow() }
    await fetcher.waitUntilSearching()
    sync.cancel()
    do {
      _ = try await sync.value
      XCTFail("a cancelled sync was supposed to throw")
    } catch {
      XCTAssertTrue(error is CancellationError, "got \(error)")
    }

    XCTAssertEqual(fetcher.connectCount, 1, "a cancelled sync is not a dead socket")
    let connected = MailConnectionState.connected(
      address: CursorTestCredentials.credentials.address, lastSync: nil)
    var seen: [MailConnectionState] = []
    for _ in 0..<4 {
      if let next = await states.next() { seen.append(next) }
    }
    XCTAssertEqual(seen, [.disconnected, .connecting, connected, connected])
  }

  private func makeService(fetcher: any MailFetching) -> IMAPMailConnectionService {
    IMAPMailConnectionService(
      fetcher: fetcher,
      engine: MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline()),
      credentials: CursorTestCredentialStore(),
      now: { Date(timeIntervalSince1970: 1_787_000_000) }
    )
  }
}

// MARK: - Doubles

private enum CursorTestCredentials {
  static let credentials = IMAPCredentials(
    host: "imap.example.com", port: 993, address: "someone@example.com", password: "app-password")
}

/// In-memory, because the Keychain is not reachable from a test binary.
private final class CursorTestCredentialStore: MailCredentialStoring, @unchecked Sendable {
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

/// Records every cursor the engine hands to its sink, in order.
private final class CursorSink: @unchecked Sendable {
  private let lock = NSLock()
  private var cursors: [MailSyncCursor] = []

  var recorded: [MailSyncCursor] {
    lock.lock()
    defer { lock.unlock() }
    return cursors
  }

  var callback: @Sendable (MailSyncCursor) -> Void {
    { [self] cursor in
      lock.lock()
      cursors.append(cursor)
      lock.unlock()
    }
  }
}

/// Serves one batch of UIDs, then cancels the task it is running in while
/// handing that batch back. The cancellation therefore lands at a known place:
/// after batch one is complete, before batch two is fetched.
///
/// `withUnsafeCurrentTask` is used because the engine calls `fetch` on the
/// caller's task, so the current task is the backfill that was started.
private final class CancelOnFirstFetch: MailFetching, @unchecked Sendable {
  let state = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 99_999)
  private let template: MailMessage
  private let allUIDs: [UInt32]
  private let lock = NSLock()
  private var fetches = 0

  init(uids: [UInt32], template: MailMessage) {
    self.allUIDs = uids
    self.template = template
  }

  var fetchCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return fetches
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  func selectMailbox(_ name: String) async throws -> MailboxState { state }
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] { allUIDs }
  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] { allUIDs }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    allUIDs.filter { $0 > uid }
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    let call = countFetch()
    if call == 1 {
      withUnsafeCurrentTask { $0?.cancel() }
    }
    return uids.map { uid in
      MailMessage(
        uid: uid,
        uidValidity: template.uidValidity,
        mailboxName: template.mailboxName,
        fromRaw: template.fromRaw,
        subject: template.subject,
        headerDate: template.headerDate,
        htmlBody: template.htmlBody,
        textBody: template.textBody
      )
    }
  }

  // Synchronous so the lock is never taken inside an async function.
  private func countFetch() -> Int {
    lock.lock()
    defer { lock.unlock() }
    fetches += 1
    return fetches
  }
}

/// Holds the first search open until the test cancels the task that is
/// searching. Like the real transport, it does not itself respond to
/// cancellation: it returns normally, and the engine's own checkpoint is what
/// stops the run.
private final class HoldInSearch: MailFetching, @unchecked Sendable {
  let state = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 99_999)
  private let searching = SearchEntered()
  private let lock = NSLock()
  private var connects = 0

  var connectCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return connects
  }

  func waitUntilSearching() async {
    await searching.wait()
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    countConnect()
  }

  func disconnect() async throws {}
  func selectMailbox(_ name: String) async throws -> MailboxState { state }

  /// Only the windowed search is used by the engine, so this one is never
  /// reached by these tests. It returns nothing, which is the honest answer for
  /// a mailbox that holds nothing.
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] { [] }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    await searching.enter()
    // Five seconds rather than minutes, so a broken cancellation fails the
    // test instead of hanging CI. Cancellation ends the sleep early.
    _ = try? await Task.sleep(nanoseconds: 5_000_000_000)
    return []
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] { [] }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] { [] }

  private func countConnect() {
    lock.lock()
    connects += 1
    lock.unlock()
  }
}

/// A one-shot "a search has started" signal. The same shape as `StartSignal` in
/// the app tests, which this target cannot see.
private actor SearchEntered {
  private var entered = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func enter() {
    guard !entered else { return }
    entered = true
    let waiting = waiters
    waiters = []
    waiting.forEach { $0.resume() }
  }

  func wait() async {
    guard !entered else { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waiters.append(continuation)
    }
  }
}
