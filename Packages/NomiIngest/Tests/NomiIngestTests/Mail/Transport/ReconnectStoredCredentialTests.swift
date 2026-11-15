import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Stored-credential reconnect (R5d, I-3) on the IMAP connection service.
///
/// Three things are pinned here. The saved password is read from the store,
/// never supplied by the caller. A rejected password is removed by the rule
/// `connect` already applies, so a second "Try again" finds nothing. And no
/// developer text reaches `MailError.unknown`: the user-facing text for an
/// unknown failure is empty, and `MailErrorMessage` turns that into the generic
/// sentence.
///
/// Every await that could wait on the state stream or on a reconnect runs under
/// `bounded`, so a state that never arrives fails the test in five seconds
/// instead of hanging the run.
///
/// The doubles are file-private: the ones in `IMAPMailConnectionServiceTests`
/// are private to that file.

private let savedCredentials = IMAPCredentials(
  host: "imap.example.com", port: 993, address: "someone@example.com", password: "app-password")

/// Thrown when a bounded await does not finish in time.
private struct Stalled: Error {}

/// Runs `work` and fails with `Stalled` if it has not returned in five seconds.
private func bounded<T: Sendable>(
  _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await work() }
    group.addTask {
      try await Task.sleep(nanoseconds: 5_000_000_000)
      throw Stalled()
    }
    defer { group.cancelAll() }
    guard let value = try await group.next() else { throw Stalled() }
    return value
  }
}

/// The first `count` states the service yields, bounded. Fewer than `count`
/// fails as `Stalled` rather than waiting forever for the rest.
private func states(
  _ service: IMAPMailConnectionService, _ count: Int
) async throws -> [MailConnectionState] {
  try await bounded {
    var seen: [MailConnectionState] = []
    for await state in service.state.prefix(count) { seen.append(state) }
    return seen
  }
}

private final class ReconnectCredentialStore: MailCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var stored: IMAPCredentials?
  private(set) var saveCount = 0
  private(set) var deleteCount = 0

  init(stored: IMAPCredentials? = nil) {
    self.stored = stored
  }

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

  var password: String? {
    lock.lock()
    defer { lock.unlock() }
    return stored?.password
  }
}

/// A store whose Keychain read fails. `hasStoredCredential` must read that as
/// "nothing saved", not crash and not claim a credential exists.
private struct UnreadableCredentialStore: MailCredentialStoring {
  func save(_ credentials: IMAPCredentials) throws {
    throw MailCredentialError.keychain(-25300)
  }

  func load() throws -> IMAPCredentials? {
    throw MailCredentialError.keychain(-25300)
  }

  func delete() throws {
    throw MailCredentialError.keychain(-25300)
  }
}

/// Refuses connects on request and otherwise serves a stub mailbox. Counting
/// goes through synchronous helpers: taking an `NSLock` in an async function is
/// an error under the Swift 6 language mode.
private final class ReconnectFetcher: MailFetching, @unchecked Sendable {
  private let lock = NSLock()
  private let inner = StubFetcher(messages: [])
  private var error: Error?
  private var connects = 0

  var connectError: Error? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return error
    }
    set {
      lock.lock()
      error = newValue
      lock.unlock()
    }
  }

  /// Every `connect` the service made, refused or not.
  var connectCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return connects
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    if let refusal = countConnectAndTakeError() { throw refusal }
  }

  func disconnect() async throws {}

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

  private func countConnectAndTakeError() -> Error? {
    lock.lock()
    defer { lock.unlock() }
    connects += 1
    return error
  }
}

/// An error that is not an `IMAPTransportError`, standing in for what an
/// offline channel open throws. It is not a verdict on the password.
private struct OfflineStandIn: Error {}

final class ReconnectStoredCredentialTests: XCTestCase {

  private func makeService(
    fetcher: ReconnectFetcher = ReconnectFetcher(),
    store: any MailCredentialStoring = ReconnectCredentialStore()
  ) -> (IMAPMailConnectionService, ReconnectFetcher) {
    let service = IMAPMailConnectionService(
      fetcher: fetcher,
      engine: MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline()),
      credentials: store,
      now: { Date(timeIntervalSince1970: 1_787_000_000) }
    )
    return (service, fetcher)
  }

  /// The error a reconnect throws, or nil if it succeeded, bounded.
  private func reconnectError(_ service: IMAPMailConnectionService) async throws -> (any Error)? {
    try await bounded {
      do {
        try await service.reconnectWithStoredCredential()
        return nil
      } catch {
        return error
      }
    }
  }

  // MARK: - hasStoredCredential

  func testHasStoredCredentialIsFalseWhenNothingIsSaved() {
    let (service, _) = makeService()
    XCTAssertFalse(service.hasStoredCredential)
  }

  func testHasStoredCredentialIsTrueWhenAPasswordIsSaved() {
    let (service, _) = makeService(store: ReconnectCredentialStore(stored: savedCredentials))
    XCTAssertTrue(service.hasStoredCredential)
  }

  /// A Keychain that cannot be read is the same to the screen as an empty one:
  /// there is nothing it can reconnect with.
  func testHasStoredCredentialIsFalseWhenTheKeychainCannotBeRead() async throws {
    let (service, _) = makeService(store: UnreadableCredentialStore())

    XCTAssertFalse(service.hasStoredCredential)
    let error = try await reconnectError(service)
    XCTAssertEqual(error as? MailError, .connectionFailed)
  }

  func testHasStoredCredentialFollowsConnectAndDisconnect() async throws {
    let (service, _) = makeService(store: ReconnectCredentialStore())

    XCTAssertFalse(service.hasStoredCredential)
    try await bounded { [service] in try await service.connect(savedCredentials) }
    XCTAssertTrue(service.hasStoredCredential)
    try await bounded { [service] in try await service.disconnect() }
    XCTAssertFalse(service.hasStoredCredential)
  }

  // MARK: - No saved credential

  /// Nothing saved: throw `connectionFailed`, touch no socket, and emit no
  /// state. The screen shows the form, so no spinner and no failure banner.
  func testNoSavedCredentialThrowsConnectionFailedAndSendsNothing() async throws {
    let store = ReconnectCredentialStore()
    let (service, fetcher) = makeService(store: store)

    let error = try await reconnectError(service)

    XCTAssertEqual(error as? MailError, .connectionFailed)
    XCTAssertEqual(fetcher.connectCount, 0, "no socket is opened without a password")
    XCTAssertEqual(store.saveCount, 0)

    let seen = try await states(service, 1)
    XCTAssertEqual(seen, [.disconnected], "no .connecting or .failed for a reconnect that never started")
  }

  // MARK: - Reconnect with a saved credential

  func testSavedCredentialConnectsAndYieldsConnectingThenConnected() async throws {
    let (service, fetcher) = makeService(store: ReconnectCredentialStore(stored: savedCredentials))

    try await bounded { [service] in try await service.reconnectWithStoredCredential() }

    XCTAssertEqual(fetcher.connectCount, 1)
    let seen = try await states(service, 3)
    XCTAssertEqual(
      seen,
      [.disconnected, .connecting, .connected(address: "someone@example.com", lastSync: nil)])
  }

  /// X16. A reconnect that fails must not look like one that worked: the last
  /// state is `.failed`, never `.connected`, and the password stays because a
  /// refused socket says nothing about it.
  func testAFailedReconnectNeverReportsConnectedAndKeepsThePassword() async throws {
    let store = ReconnectCredentialStore(stored: savedCredentials)
    let fetcher = ReconnectFetcher()
    fetcher.connectError = IMAPTransportError.connectionClosed
    let (service, _) = makeService(fetcher: fetcher, store: store)

    let error = try await reconnectError(service)

    XCTAssertNotNil(error)
    XCTAssertEqual(store.deleteCount, 0)
    XCTAssertEqual(store.password, "app-password")
    let seen = try await states(service, 3)
    XCTAssertEqual(seen, [.disconnected, .connecting, .failed(.connectionFailed)])
  }

  /// X16, the half-switched case. A live connection whose reconnect is refused
  /// must not keep its old address: no `.connecting` is left pending, and a sync
  /// after the failure is refused as not connected rather than run on a socket
  /// that is gone.
  func testAFailedReconnectOfALiveConnectionLeavesNothingConnected() async throws {
    let fetcher = ReconnectFetcher()
    let (service, _) = makeService(fetcher: fetcher, store: ReconnectCredentialStore())
    try await bounded { [service] in try await service.connect(savedCredentials) }

    fetcher.connectError = IMAPTransportError.connectionClosed
    let error = try await reconnectError(service)
    XCTAssertNotNil(error)

    do {
      _ = try await bounded { [service] in try await service.syncNow() }
      XCTFail("syncNow must not run on a connection the failed reconnect abandoned")
    } catch let transport as IMAPTransportError {
      XCTAssertEqual(transport, .notConnected)
    }

    let seen = try await states(service, 5)
    XCTAssertEqual(
      seen,
      [
        .disconnected,
        .connecting,
        .connected(address: "someone@example.com", lastSync: nil),
        .connecting,
        .failed(.connectionFailed),
      ])
  }

  /// The rule `connect` already has, reached through the reconnect: a password
  /// the server rejects is removed, and a second "Try again" finds nothing and
  /// sends nothing.
  func testRejectedSavedCredentialIsDeleted() async throws {
    let store = ReconnectCredentialStore(stored: savedCredentials)
    let fetcher = ReconnectFetcher()
    fetcher.connectError = IMAPTransportError.authenticationFailed("Invalid credentials")
    let (service, _) = makeService(fetcher: fetcher, store: store)

    let first = try await reconnectError(service)
    XCTAssertNotNil(first)
    XCTAssertTrue(store.isEmpty, "a rejected password is not kept")
    XCTAssertFalse(service.hasStoredCredential)

    let second = try await reconnectError(service)
    XCTAssertEqual(second as? MailError, .connectionFailed)
    XCTAssertEqual(fetcher.connectCount, 1, "the second attempt never reaches the server")

    let seen = try await states(service, 3)
    XCTAssertEqual(seen, [.disconnected, .connecting, .failed(.authenticationFailed)])
  }

  // MARK: - User-facing error text

  /// `commandFailed`, `malformedResponse` and an error that is not a transport
  /// error at all all reach the state as `.unknown("")`. The developer string a
  /// `String(describing:)` would have produced stays out of the Settings screen.
  func testUnknownErrorsCarryNoDeveloperText() async throws {
    let failures: [any Error] = [
      IMAPTransportError.commandFailed(tag: "A3", status: .bad, text: "SELECT wrong state"),
      IMAPTransportError.malformedResponse("unparseable greeting"),
      OfflineStandIn(),
    ]

    for failure in failures {
      let fetcher = ReconnectFetcher()
      fetcher.connectError = failure
      let (service, _) = makeService(
        fetcher: fetcher, store: ReconnectCredentialStore(stored: savedCredentials))

      _ = try await reconnectError(service)

      let seen = try await states(service, 3)
      XCTAssertEqual(seen.last, .failed(.unknown("")), "\(failure) must not leak its description")
    }
  }

  /// The one transport error that is always the user's own input keeps its
  /// copy, because that copy is written for the user.
  func testInvalidCredentialsKeepTheirUserText() async throws {
    let store = ReconnectCredentialStore(stored: savedCredentials)
    let fetcher = ReconnectFetcher()
    fetcher.connectError = IMAPTransportError.invalidCredentials(
      "The password contains a line break.")
    let (service, _) = makeService(fetcher: fetcher, store: store)

    _ = try await reconnectError(service)

    XCTAssertTrue(store.isEmpty, "a credential that cannot be sent is not kept")
    let seen = try await states(service, 3)
    XCTAssertEqual(seen.last, .failed(.unknown("The password contains a line break.")))
  }
}
