import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// R10 (X16). A background refresh on a cold launch has not run `bootstrap()`,
/// so no mailbox is connected yet. Before this unit the refresh found none,
/// reported nothing, and the mail stayed stale until the app was opened by hand.
/// A failed sync also reported success to iOS, which counts that against the
/// app's scheduling budget.
///
/// Everything here drives `run(_:)` through `BackgroundWork`'s non-iOS record,
/// the same seam `BackgroundWorkRoutingTests` uses, so the block is compiled off
/// iOS only. On iOS the real `BGTask` is handed out by the system and cannot be
/// built in a test. The real cold launch is a device check and is not run here.
final class BackgroundColdLaunchTests: XCTestCase {

  #if !os(iOS)

    /// The reconnect is what makes the refresh work: the fetcher sees a connect
    /// before any search, and the work completes successfully.
    func testColdRefreshConnectsThenSyncs() async throws {
      let fetcher = OrderRecordingMailFetcher()
      let credentials = MemoryCredentialStore()
      try credentials.save(.test)
      let stack = MailStack(
        fetcher: fetcher,
        pipeline: SilentPipeline(),
        credentials: credentials,
        preferences: InMemoryKeyValueStore()
      )
      let coordinator = AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        submitter: RecordingSubmitter(),
        ensureMailConnected: { await stack.reconnectFromKeychain(credentials) }
      )
      let record = BackgroundWorkRecord()

      await coordinator.run(BackgroundWork(kind: .refresh, record: record))

      XCTAssertEqual(fetcher.calls.first, .connect, "the reconnect comes first")
      XCTAssertEqual(
        fetcher.calls.filter { $0 == .connect }.count, 1, "connected once: \(fetcher.calls)")
      XCTAssertTrue(
        fetcher.calls.dropFirst().contains(where: \.isSearch),
        "and a sync follows it: \(fetcher.calls)")
      XCTAssertEqual(record.recordedCompletions, [true])
    }

    /// A user who never connected mail has nothing stored, so there is nothing to
    /// reconnect to and nothing owed. That is a quiet success, not a failure
    /// that iOS should count against the app.
    func testColdRefreshWithNoCredentialIsNotAFailure() async throws {
      let fetcher = OrderRecordingMailFetcher()
      let credentials = MemoryCredentialStore()
      let stack = MailStack(
        fetcher: fetcher,
        pipeline: SilentPipeline(),
        credentials: credentials,
        preferences: InMemoryKeyValueStore()
      )
      let coordinator = AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        submitter: RecordingSubmitter(),
        ensureMailConnected: { await stack.reconnectFromKeychain(credentials) }
      )
      let record = BackgroundWorkRecord()

      await coordinator.run(BackgroundWork(kind: .refresh, record: record))

      XCTAssertEqual(fetcher.calls, [], "nothing stored, so nothing was asked of the server")
      XCTAssertEqual(record.recordedCompletions, [true])
    }

    /// A sync that fails is reported as failed, once. Reporting success here
    /// would tell iOS the work was done when it was not.
    func testAFailedSyncCompletesUnsuccessfully() async throws {
      let credentials = MemoryCredentialStore()
      try credentials.save(.test)
      let stack = MailStack(
        fetcher: CommandFailingFetcher(),
        pipeline: SilentPipeline(),
        credentials: credentials,
        preferences: InMemoryKeyValueStore()
      )
      try await stack.service.connect(.test)
      let coordinator = AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        submitter: RecordingSubmitter(),
        ensureMailConnected: { await stack.reconnectFromKeychain(credentials) }
      )
      let record = BackgroundWorkRecord()

      await coordinator.run(BackgroundWork(kind: .refresh, record: record))

      XCTAssertEqual(record.recordedCompletions, [false])
    }
  #endif
}

// MARK: - Doubles

/// Connects, then refuses every mailbox command the way a server rejects one
/// with a tagged `NO`. Used only to drive a sync into `.failed`.
private final class CommandFailingFetcher: MailFetching, @unchecked Sendable {
  private var refusal: IMAPTransportError {
    .commandFailed(tag: "A2", status: .no, text: "[UNAVAILABLE] try again later")
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}

  func selectMailbox(_ name: String) async throws -> MailboxState {
    MailboxState(name: name, uidValidity: 7, uidNext: 1)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    throw refusal
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    throw refusal
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    throw refusal
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    throw refusal
  }
}
