import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Connects and disconnects that overlap.
///
/// The erase path stops waiting for a disconnect that has not returned in 10 s
/// and carries on. The disconnect may return later, into a service that by then
/// holds a different mailbox, or that has been overtaken by a connect. These
/// tests pin what a late return or a late connect may touch.
final class IMAPMailDisconnectRaceTests: XCTestCase {

  private let oldMailbox = IMAPCredentials(
    host: "imap.gmail.com", port: 993, address: "old@example.com", password: "old-password")
  private let newMailbox = IMAPCredentials(
    host: "imap.gmail.com", port: 993, address: "new@example.com", password: "new-password")

  private func makeService(
    fetcher: any MailFetching,
    store: DisconnectRaceCredentialStore
  ) -> IMAPMailConnectionService {
    IMAPMailConnectionService(
      fetcher: fetcher,
      engine: MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline()),
      credentials: store,
      now: { Date(timeIntervalSince1970: 1_787_000_000) })
  }

  /// The bug. A disconnect is parked in the transport, a new mailbox connects, and
  /// then the old disconnect returns. It must leave the new password in the store
  /// and must not publish `.disconnected` over the new connection.
  ///
  /// Fails on the old code: the late return deletes `new-password` and publishes
  /// `.disconnected`, so `syncNow` is refused with `notConnected`.
  func testASlowDisconnectFinishingAfterANewConnectLeavesTheNewConnectionAlone() async throws {
    let fetcher = ScriptedFetcher()
    let store = DisconnectRaceCredentialStore()
    let service = makeService(fetcher: fetcher, store: store)

    try await service.connect(oldMailbox)
    let parked = fetcher.holdNextDisconnect()
    let disconnect = Task { try await service.disconnect() }
    _ = try await collect(fetcher.disconnectBegan, count: 1)

    try await service.connect(newMailbox)
    await parked.open()
    try await disconnect.value

    XCTAssertEqual(
      try store.load()?.password, "new-password",
      "the late disconnect removed the password of the mailbox connected after it")
    do {
      _ = try await service.syncNow()
    } catch {
      XCTFail("the late disconnect took the new connection down: \(error)")
    }

    // Six values, so a late `.disconnected` (if it were published) is inside the
    // window. The sixth is the sync's own `.connected`.
    let seen = try await collect(service.state, count: 6)
    XCTAssertEqual(
      seen,
      [
        .disconnected,
        .connecting,
        .connected(address: "old@example.com", lastSync: nil),
        .connecting,
        .connected(address: "new@example.com", lastSync: nil),
        .connected(
          address: "new@example.com", lastSync: Date(timeIntervalSince1970: 1_787_000_000)),
      ])
  }

  /// A connect that a newer connect has overtaken must not let its failure delete
  /// the newer password. Before the fix, a rejected password from the older
  /// attempt removed the password the newer attempt had just saved.
  func testARejectedPasswordFromASupersededConnectLeavesTheNewerCredential() async throws {
    let fetcher = ScriptedFetcher()
    let store = DisconnectRaceCredentialStore()
    let service = makeService(fetcher: fetcher, store: store)

    fetcher.setConnectError(IMAPTransportError.authenticationFailed("Invalid credentials"))
    let parked = fetcher.holdNextConnect()
    let oldAttempt = Task { try await service.connect(oldMailbox) }
    _ = try await collect(fetcher.connectBegan, count: 1)

    fetcher.setConnectError(nil)
    try await service.connect(newMailbox)
    await parked.open()
    let oldOutcome = await oldAttempt.result

    XCTAssertEqual(
      try store.load()?.password, "new-password",
      "the superseded connect's rejected password removed the newer password")
    if case .failure(let error) = oldOutcome {
      XCTAssertTrue(
        error is CancellationError,
        "a superseded connect reports that it was overtaken, not its own failure: \(error)")
    } else {
      XCTFail("the superseded connect should not report success")
    }
    do {
      _ = try await service.syncNow()
    } catch {
      XCTFail("the superseded failure took the newer connection down: \(error)")
    }

    // The superseded attempt publishes nothing: no `.failed` after the newer
    // connection's `.connected`. The fifth value is the sync's own `.connected`.
    let seen = try await collect(service.state, count: 5)
    XCTAssertEqual(
      seen,
      [
        .disconnected,
        .connecting,
        .connecting,
        .connected(address: "new@example.com", lastSync: nil),
        .connected(
          address: "new@example.com", lastSync: Date(timeIntervalSince1970: 1_787_000_000)),
      ])
  }

  /// A connect that a disconnect has overtaken must not publish `.connected` when
  /// its network call returns, and must not leave its password in the store.
  /// Before the fix it published `.connected(old)` after the disconnect's
  /// `.disconnected`, so the service reported a connection the store had dropped.
  func testAConnectOvertakenByADisconnectPublishesNothingAndStoresNothing() async throws {
    let fetcher = ScriptedFetcher()
    let store = DisconnectRaceCredentialStore()
    let service = makeService(fetcher: fetcher, store: store)

    let parked = fetcher.holdNextConnect()
    let attempt = Task { try await service.connect(oldMailbox) }
    _ = try await collect(fetcher.connectBegan, count: 1)

    try await service.disconnect()
    await parked.open()
    let outcome = await attempt.result

    XCTAssertNil(try store.load(), "the overtaken connect put its password back")
    if case .failure(let error) = outcome {
      XCTAssertTrue(
        error is CancellationError,
        "an overtaken connect reports that it was overtaken: \(error)")
    } else {
      XCTFail("the overtaken connect should not report success")
    }

    // A sentinel connect after it, so the stream carries everything the late
    // return could have published. Five values: the overtaken connect publishes
    // nothing, so the sequence has no `.connected(old)`.
    try await service.connect(newMailbox)
    let seen = try await collect(service.state, count: 5)
    XCTAssertEqual(
      seen,
      [
        .disconnected,
        .connecting,
        .disconnected,
        .connecting,
        .connected(address: "new@example.com", lastSync: nil),
      ])
  }

  /// The path that must keep working: a disconnect with no newer connect behind it
  /// deletes the password and publishes `.disconnected`, as it always has.
  func testADisconnectWithNoNewerConnectDeletesTheCredentialAndPublishesDisconnected()
    async throws
  {
    let fetcher = ScriptedFetcher()
    let store = DisconnectRaceCredentialStore()
    let service = makeService(fetcher: fetcher, store: store)

    try await service.connect(oldMailbox)
    try await service.disconnect()

    XCTAssertNil(try store.load(), "a normal disconnect must remove the stored password")
    let seen = try await collect(service.state, count: 4)
    XCTAssertEqual(
      seen,
      [
        .disconnected,
        .connecting,
        .connected(address: "old@example.com", lastSync: nil),
        .disconnected,
      ])
  }
}

/// A transport whose `connect` and `disconnect` the test can park, and whose
/// `connect` can be made to fail. Everything else is the stub's.
///
/// A hold is armed for the next call only, so a test can park one attempt and
/// let later calls through.
private final class ScriptedFetcher: MailFetching, @unchecked Sendable {
  private let inner = StubFetcher(messages: [])
  private let lock = NSLock()
  private var connectError: Error?
  private var armedConnect: CallGate?
  private var armedDisconnect: CallGate?

  /// One value per parked call, yielded before the call waits.
  let connectBegan: AsyncStream<Void>
  let disconnectBegan: AsyncStream<Void>
  private let connectBeganSink: AsyncStream<Void>.Continuation
  private let disconnectBeganSink: AsyncStream<Void>.Continuation

  init() {
    var connectSink: AsyncStream<Void>.Continuation!
    connectBegan = AsyncStream(bufferingPolicy: .unbounded) { connectSink = $0 }
    connectBeganSink = connectSink
    var disconnectSink: AsyncStream<Void>.Continuation!
    disconnectBegan = AsyncStream(bufferingPolicy: .unbounded) { disconnectSink = $0 }
    disconnectBeganSink = disconnectSink
  }

  /// Parks the next `connect` until the returned gate opens.
  func holdNextConnect() -> CallGate {
    let gate = CallGate()
    lock.lock()
    armedConnect = gate
    lock.unlock()
    return gate
  }

  /// Parks the next `disconnect` until the returned gate opens.
  func holdNextDisconnect() -> CallGate {
    let gate = CallGate()
    lock.lock()
    armedDisconnect = gate
    lock.unlock()
    return gate
  }

  /// The error later `connect` calls throw. A call reads it when it begins.
  func setConnectError(_ error: Error?) {
    lock.lock()
    connectError = error
    lock.unlock()
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    let (error, gate) = takeConnectSettings()
    if let gate {
      connectBeganSink.yield(())
      await gate.wait()
    }
    if let error { throw error }
  }

  func disconnect() async throws {
    if let gate = takeDisconnectHold() {
      disconnectBeganSink.yield(())
      await gate.wait()
    }
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
    try await inner.fetch(uids: uids, in: mailbox)
  }

  // Synchronous helpers, so no `NSLock` is taken in an async function.

  private func takeConnectSettings() -> (Error?, CallGate?) {
    lock.lock()
    defer { lock.unlock() }
    let gate = armedConnect
    armedConnect = nil
    return (connectError, gate)
  }

  private func takeDisconnectHold() -> CallGate? {
    lock.lock()
    defer { lock.unlock() }
    let gate = armedDisconnect
    armedDisconnect = nil
    return gate
  }
}

/// Holds callers in `wait` until `open`. Once open, every later `wait` returns at once.
private actor CallGate {
  private var isOpen = false
  private var parked: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { parked.append($0) }
  }

  func open() {
    isOpen = true
    let waiting = parked
    parked = []
    for continuation in waiting { continuation.resume() }
  }
}

/// In-memory credential store. Kept separate from the file-private store in
/// `IMAPMailConnectionServiceTests` so this file stands on its own.
private final class DisconnectRaceCredentialStore: MailCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: IMAPCredentials?

  func save(_ credentials: IMAPCredentials) throws {
    lock.lock()
    defer { lock.unlock() }
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
    stored = nil
  }
}
