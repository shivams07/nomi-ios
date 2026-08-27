import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// In-memory credential store. The real one talks to the Keychain, which a test
/// binary cannot reach at all — see `KeychainCredentialStore`.
private final class MemoryCredentialStore: MailCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: IMAPCredentials?
  private(set) var saveCount = 0
  private(set) var deleteCount = 0

  func save(_ credentials: IMAPCredentials) throws {
    lock.lock()
    defer { lock.unlock() }
    saveCount += 1
    stored = credentials
  }

  func load() throws -> IMAPCredentials? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func delete() throws {
    lock.lock()
    defer { lock.unlock() }
    deleteCount += 1
    stored = nil
  }

  var isEmpty: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stored == nil
  }
}

/// A fetcher whose `connect` can be made to fail.
private final class FlakyFetcher: MailFetching, @unchecked Sendable {
  private let inner: StubFetcher
  var connectError: Error?
  private(set) var disconnectCount = 0

  init(messages: [MailMessage] = []) {
    inner = StubFetcher(messages: messages)
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    if let connectError { throw connectError }
  }

  func disconnect() async throws { disconnectCount += 1 }

  func selectMailbox(_ name: String) async throws -> MailboxState {
    try await inner.selectMailbox(name)
  }
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    try await inner.uids(since: date, in: mailbox)
  }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    try await inner.uids(after: uid, in: mailbox)
  }
  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    try await inner.fetch(uids: uids, in: mailbox)
  }
}

final class IMAPMailConnectionServiceTests: XCTestCase {

  private let credentials = IMAPCredentials(
    host: "imap.gmail.com", port: 993, address: "shivam@example.com", password: "app-password")

  private func makeService(
    messages: [MailMessage] = [],
    fetcher: FlakyFetcher? = nil,
    store: MemoryCredentialStore = MemoryCredentialStore(),
    pipeline: RecordingPipeline = RecordingPipeline()
  ) -> (IMAPMailConnectionService, FlakyFetcher, MemoryCredentialStore, RecordingPipeline) {
    let fetcher = fetcher ?? FlakyFetcher(messages: messages)
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: pipeline)
    let service = IMAPMailConnectionService(
      fetcher: fetcher,
      engine: engine,
      credentials: store,
      now: { Date(timeIntervalSince1970: 1_787_000_000) }
    )
    return (service, fetcher, store, pipeline)
  }

  // MARK: - Connect

  func testConnectStoresTheCredentialAndReportsConnected() async throws {
    let (service, _, store, _) = makeService()

    try await service.connect(credentials)

    XCTAssertEqual(store.saveCount, 1)
    XCTAssertFalse(store.isEmpty)

    var seen: [MailConnectionState] = []
    for await state in service.state.prefix(3) { seen.append(state) }
    XCTAssertEqual(seen[0], .disconnected)
    XCTAssertEqual(seen[1], .connecting)
    XCTAssertEqual(seen[2], .connected(address: "shivam@example.com", lastSync: nil))
  }

  /// Storing a password the server just rejected buys nothing but a background
  /// sync that fails forever without telling anyone.
  func testAFailedConnectRemovesTheCredentialItJustStored() async {
    let fetcher = FlakyFetcher()
    fetcher.connectError = IMAPTransportError.authenticationFailed("Invalid credentials")
    let (service, _, store, _) = makeService(fetcher: fetcher)

    do {
      try await service.connect(credentials)
      XCTFail("connect should have thrown")
    } catch {
      // expected
    }

    XCTAssertEqual(store.saveCount, 1)
    XCTAssertEqual(store.deleteCount, 1)
    XCTAssertTrue(store.isEmpty)
  }

  func testAFailedConnectReportsAuthenticationFailureRatherThanAGenericOne() async {
    let fetcher = FlakyFetcher()
    fetcher.connectError = IMAPTransportError.authenticationFailed("Invalid credentials")
    let (service, _, _, _) = makeService(fetcher: fetcher)

    try? await service.connect(credentials)

    var seen: [MailConnectionState] = []
    for await state in service.state.prefix(3) { seen.append(state) }
    XCTAssertEqual(seen[2], .failed(.authenticationFailed))
  }

  // MARK: - Disconnect

  /// "Stops capture. Deletes nothing." The credential goes; the ledger does not.
  func testDisconnectClearsTheCredentialAndTouchesNoTransactions() async throws {
    let (service, fetcher, store, pipeline) = makeService(
      messages: [try MailFixtures.message("hdfc_debit_netbanking.eml", uid: 10)])

    try await service.connect(credentials)
    _ = try await service.syncNow()
    let ingestedBatches = pipeline.received.count

    try await service.disconnect()

    XCTAssertTrue(store.isEmpty)
    XCTAssertEqual(fetcher.disconnectCount, 1)
    // Nothing was un-ingested. Disconnect is not a delete.
    XCTAssertEqual(pipeline.received.count, ingestedBatches)
  }

  func testSyncAfterDisconnectIsRefused() async throws {
    let (service, _, _, _) = makeService()

    try await service.connect(credentials)
    try await service.disconnect()

    do {
      _ = try await service.syncNow()
      XCTFail("syncNow should have thrown")
    } catch let error as IMAPTransportError {
      XCTAssertEqual(error, .notConnected)
    }
  }

  func testSyncBeforeConnectIsRefused() async {
    let (service, _, _, _) = makeService()

    do {
      _ = try await service.syncNow()
      XCTFail("syncNow should have thrown")
    } catch let error as IMAPTransportError {
      XCTAssertEqual(error, .notConnected)
    }
  }

  // MARK: - Sync

  func testSyncNowDelegatesToTheEngineAndReturnsItsSummary() async throws {
    let pipeline = RecordingPipeline()
    pipeline.result = IngestBatchResult(created: 1, merged: 0, flagged: 1)
    let (service, _, _, _) = makeService(
      messages: [try MailFixtures.message("hdfc_debit_netbanking.eml", uid: 10)],
      pipeline: pipeline)

    try await service.connect(credentials)
    let summary = try await service.syncNow()

    XCTAssertEqual(summary.scanned, 1)
    XCTAssertEqual(summary.packMatched, 1)
    XCTAssertEqual(summary.created, 1)
  }

  func testSyncRecordsLastSyncOnTheConnectedState() async throws {
    let (service, _, _, _) = makeService()

    try await service.connect(credentials)
    _ = try await service.syncNow()

    var seen: [MailConnectionState] = []
    for await state in service.state.prefix(4) { seen.append(state) }
    XCTAssertEqual(
      seen[3],
      .connected(
        address: "shivam@example.com", lastSync: Date(timeIntervalSince1970: 1_787_000_000)))
  }

  // MARK: - Backfill

  func testBackfillReportsProgressAndCounts() async throws {
    let pipeline = RecordingPipeline()
    pipeline.result = IngestBatchResult(created: 2, merged: 0, flagged: 2)
    let (service, _, _, _) = makeService(
      messages: [
        try MailFixtures.message("hdfc_debit_netbanking.eml", uid: 10),
        try MailFixtures.message("kotak_debit_card.eml", uid: 11),
      ],
      pipeline: pipeline)

    try await service.connect(credentials)
    try await service.startBackfill(months: 6)

    var progress: [BackfillProgress] = []
    for await tick in service.backfillProgress.prefix(2) { progress.append(tick) }

    XCTAssertEqual(progress[0].scanned, 0)
    XCTAssertEqual(progress[1].scanned, 2)
    XCTAssertEqual(progress[1].total, 2)
    XCTAssertEqual(progress[1].created, 2)
  }

  func testBackfillBeforeConnectIsRefused() async {
    let (service, _, _, _) = makeService()

    do {
      try await service.startBackfill(months: 6)
      XCTFail("startBackfill should have thrown")
    } catch let error as IMAPTransportError {
      XCTAssertEqual(error, .notConnected)
    }
  }

  // MARK: - The unimplemented reader

  /// The response parser is a blocked design decision, not a missing line. It
  /// fails loudly: a mail client that silently reports "0 new transactions"
  /// because it could not read a single response is worse than one that reports
  /// an error.
  func testTheUnimplementedResponseReaderRefusesRatherThanReturningNothing() {
    let reader = UnimplementedResponseReader()

    XCTAssertThrowsError(try reader.consume([0x2A, 0x20, 0x4F, 0x4B])) { error in
      XCTAssertEqual(error as? IMAPTransportError, .responseParsingUnavailable)
    }
  }
}
