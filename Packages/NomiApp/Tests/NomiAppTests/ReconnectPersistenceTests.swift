import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// R5d, through the object every screen is handed: `MailStack.service`, the
/// broadcaster over the cursor-persisting wrapper over the IMAP service.
///
/// Two things are pinned. `hasStoredCredential` answers the screen's question
/// ("is there a password I can reconnect with?") at each step of the lifecycle.
/// And a reconnect writes `mailHasConnected` only when it actually connected,
/// the same rule `connect` follows, so a failed reconnect cannot make "ever
/// connected" true.
///
/// Every call into the stack runs under `bounded`, so a call that never returns
/// fails the test in five seconds instead of hanging the run.
///
/// Doubles are the ones `MailCursorPersistenceTests` defines in this target
/// (`MemoryCredentialStore`, `RecordingMailFetcher`, `SilentPipeline`,
/// `IMAPCredentials.test`), plus one fetcher that refuses connects.
final class ReconnectPersistenceTests: XCTestCase {

  // MARK: - hasStoredCredential

  func testAFreshInstallHasNothingToReconnectWith() async throws {
    let stack = makeStack(credentials: MemoryCredentialStore(), preferences: InMemoryKeyValueStore())

    let has = try await bounded { await stack.service.hasStoredCredential }

    XCTAssertFalse(has)
  }

  func testTheCredentialIsVisibleAfterConnectAndGoneAfterDisconnect() async throws {
    let stack = makeStack(preferences: InMemoryKeyValueStore())

    try await bounded { try await stack.service.connect(.test) }
    let afterConnect = try await bounded { await stack.service.hasStoredCredential }
    XCTAssertTrue(afterConnect)

    try await bounded { try await stack.service.disconnect() }
    let afterDisconnect = try await bounded { await stack.service.hasStoredCredential }
    XCTAssertFalse(afterDisconnect)
  }

  /// A relaunch sees the password the last launch saved: `hasStoredCredential`
  /// reads the Keychain on each call, so nothing has to be replayed.
  func testASavedCredentialIsStillThereOnTheNextLaunch() async throws {
    let credentials = MemoryCredentialStore()
    let preferences = InMemoryKeyValueStore()
    let first = makeStack(credentials: credentials, preferences: preferences)
    try await bounded { try await first.service.connect(.test) }

    let relaunched = makeStack(credentials: credentials, preferences: preferences)
    let has = try await bounded { await relaunched.service.hasStoredCredential }

    XCTAssertTrue(has)
  }

  // MARK: - Reconnect and "ever connected"

  /// The reconnect path sets the flag the way `connect` does. The credential
  /// here was saved on an earlier run, before the flag existed, so the flag is
  /// false until the reconnect succeeds.
  func testAReconnectThatSucceedsSetsEverConnected() async throws {
    let credentials = MemoryCredentialStore()
    try credentials.save(.test)
    let preferences = InMemoryKeyValueStore()
    let stack = makeStack(
      fetcher: RecordingMailFetcher(uids: []), credentials: credentials, preferences: preferences)
    let before = try await bounded { await stack.service.history }
    XCTAssertFalse(before.hasEverConnected)

    try await bounded { try await stack.service.reconnectWithStoredCredential() }

    let after = try await bounded { await stack.service.history }
    XCTAssertTrue(after.hasEverConnected)
    let relaunched = makeStack(credentials: credentials, preferences: preferences)
    let afterRelaunch = try await bounded { await relaunched.service.history }
    XCTAssertTrue(afterRelaunch.hasEverConnected)
  }

  /// X16 at the persistence layer. A reconnect the server refuses is not a
  /// connection, so it must not set the flag, and the password it failed with
  /// stays because a refused socket is not a verdict on it.
  func testAFailedReconnectDoesNotSetEverConnectedAndKeepsThePassword() async throws {
    let credentials = MemoryCredentialStore()
    try credentials.save(.test)
    let preferences = InMemoryKeyValueStore()
    let stack = makeStack(
      fetcher: ConnectRefusingFetcher(
        inner: RecordingMailFetcher(uids: []), error: IMAPTransportError.connectionClosed),
      credentials: credentials,
      preferences: preferences)

    do {
      try await bounded { try await stack.service.reconnectWithStoredCredential() }
      XCTFail("the refused reconnect should have thrown")
    } catch is Stalled {
      throw Stalled()
    } catch {
      // expected: the refusal reaches the caller
    }

    let history = try await bounded { await stack.service.history }
    XCTAssertFalse(history.hasEverConnected)
    XCTAssertEqual(try credentials.load()?.password, IMAPCredentials.test.password)
  }

  /// No saved password: the reconnect throws `connectionFailed` and records
  /// nothing. The screen then shows the form.
  func testAReconnectWithNothingSavedThrowsAndRecordsNothing() async throws {
    let stack = makeStack(credentials: MemoryCredentialStore(), preferences: InMemoryKeyValueStore())

    do {
      try await bounded { try await stack.service.reconnectWithStoredCredential() }
      XCTFail("a reconnect with nothing saved should have thrown")
    } catch let error as MailError {
      XCTAssertEqual(error, .connectionFailed)
    }

    let history = try await bounded { await stack.service.history }
    XCTAssertEqual(history, .never)
  }

  /// A password the server rejected is removed on the reconnect, so the flag
  /// the screen reads turns false and the next "Try again" has nothing to use.
  func testARejectedReconnectRemovesTheCredentialThroughTheStack() async throws {
    let credentials = MemoryCredentialStore()
    try credentials.save(.test)
    let stack = makeStack(
      fetcher: ConnectRefusingFetcher(
        inner: RecordingMailFetcher(uids: []),
        error: IMAPTransportError.authenticationFailed("Invalid credentials")),
      credentials: credentials,
      preferences: InMemoryKeyValueStore())

    _ = try? await bounded { try await stack.service.reconnectWithStoredCredential() }

    let has = try await bounded { await stack.service.hasStoredCredential }
    XCTAssertFalse(has)
    let history = try await bounded { await stack.service.history }
    XCTAssertFalse(history.hasEverConnected)
  }

  // MARK: -

  private func makeStack(
    fetcher: any MailFetching = RecordingMailFetcher(uids: []),
    credentials: MemoryCredentialStore = MemoryCredentialStore(),
    preferences: InMemoryKeyValueStore
  ) -> MailStack {
    MailStack(
      fetcher: fetcher,
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: preferences
    )
  }
}

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

/// Refuses every connect with `error` and otherwise behaves as `inner`, so the
/// stack under test is the real one.
private struct ConnectRefusingFetcher: MailFetching {
  let inner: RecordingMailFetcher
  let error: any Error

  func connect(_ credentials: IMAPCredentials) async throws {
    throw error
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
