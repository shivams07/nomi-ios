import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// Launch used to end at the reconnect.
///
/// `bootstrap()` seeded, reconciled and called `reconnectFromKeychain`, and
/// nothing synced. `didBecomeActive` fires on the first `.active` scene phase —
/// which is *before* `bootstrap()` finishes — so it found no mailbox, hit
/// `IMAPTransportError.notConnected`, and `try?` threw it away. A returning user
/// saw the ledger as it was when they last used the app until they backgrounded
/// and foregrounded it by hand.
///
/// Two questions, and the second is the one that bites: is a sync issued after
/// the connect returns, and does the `didBecomeActive` that got there first stop
/// it happening.
final class BootstrapOrderTests: XCTestCase {

  // MARK: - The coordinator on its own

  /// The order, at the transport seam. `connect` is what
  /// `reconnectFromKeychain` reaches; a search is what a sync reaches. The
  /// assertion is that they arrive in that order and that the second one arrives
  /// at all.
  func testASyncIsIssuedAfterTheConnectReturns() async throws {
    let context = makeContext()

    await context.stack.reconnectFromKeychain(context.credentials)
    let attempt = await context.coordinator.syncAfterConnect()

    XCTAssertEqual(attempt, .ran)
    XCTAssertEqual(context.fetcher.calls.first, .connect)
    XCTAssertTrue(
      context.fetcher.calls.dropFirst().contains(where: \.isSearch),
      "a sync must follow the connect: \(context.fetcher.calls)")
  }

  /// The regression. A `didBecomeActive` that fires before the mailbox exists
  /// must not stand in for the post-connect sync — it is, by definition, the
  /// sync that ran with nothing connected.
  ///
  /// Without `syncAfterConnect` awaiting it, `syncIfIdle`'s guard sees
  /// `isSyncing` and returns `.alreadyRunning`, and the launch sync never
  /// happens.
  func testADidBecomeActiveArrivingFirstDoesNotConsumeTheLaunchSync() async throws {
    let context = makeContext()

    // Before any credential is stored: this is the real ordering, where the
    // scene goes active while `bootstrap()` is still working.
    context.coordinator.didBecomeActive()

    await context.stack.reconnectFromKeychain(context.credentials)
    let attempt = await context.coordinator.syncAfterConnect()

    XCTAssertEqual(attempt, .ran, "the launch sync must still run")
    XCTAssertTrue(context.fetcher.calls.contains(where: \.isSearch))
  }

  /// The half of the fix that is about naming rather than ordering. A sync
  /// refused because nothing is connected is not a failure and is not a sync —
  /// it is one that is owed, and it used to be indistinguishable from both.
  func testASyncWithNoMailboxIsReportedAsOwedRatherThanSwallowed() async throws {
    let context = makeContext()

    let attempt = await context.coordinator.syncIfIdle()

    XCTAssertEqual(attempt, .noMailboxConnected)
    XCTAssertFalse(
      context.fetcher.calls.contains(where: \.isSearch),
      "nothing is connected, so nothing should have been searched")
  }

  /// The control on the guard itself: it still exists and still does its job.
  /// Two syncs racing would each fetch the same UIDs for nothing.
  func testASecondSyncWhileOneIsRunningIsSkippedNotQueuedTwice() async throws {
    let started = StartSignal()
    let context = makeContext(blockOnSearch: started)

    await context.stack.reconnectFromKeychain(context.credentials)
    let first = Task { await context.coordinator.syncIfIdle() }
    await started.wait()

    let second = await context.coordinator.syncIfIdle()
    XCTAssertEqual(second, .alreadyRunning)

    first.cancel()
    _ = await first.value
  }

  // MARK: - The composition root

  /// `bootstrap()` itself, over a real `AppEnvironment`.
  ///
  /// The coordinator tests above prove the ordering; this one proves
  /// `bootstrap()` actually calls it, which is the part that was missing rather
  /// than wrong. A `ModelContainer` under `swift test` is fine in XCTest and
  /// traps under swift-testing — see `InMemoryModelContainer` — which is why
  /// this file is XCTest.
  @MainActor
  func testBootstrapReconnectsAndThenSyncs() async throws {
    let fetcher = OrderRecordingMailFetcher()
    let credentials = MemoryCredentialStore()
    try credentials.save(.test)

    let environment = AppEnvironment(
      container: InMemoryModelContainer.shared,
      preferences: InMemoryKeyValueStore(),
      credentials: credentials,
      mailFetcher: fetcher,
      scheduler: NoopNotificationScheduler()
    )

    await environment.bootstrap()

    XCTAssertEqual(fetcher.calls.first, .connect, "the reconnect comes first")
    XCTAssertTrue(
      fetcher.calls.dropFirst().contains(where: \.isSearch),
      "and a sync follows it: \(fetcher.calls)")
  }

  /// The other half of `bootstrap()`'s ordering: both seeds run, and the rules
  /// run after the categories they name.
  ///
  /// Asserted through the store rather than through the seed values — those have
  /// their own tests — because the question here is whether `bootstrap()` calls
  /// the second seed at all.
  @MainActor
  func testBootstrapSeedsRulesAsWellAsCategories() async throws {
    let environment = AppEnvironment(
      container: InMemoryModelContainer.shared,
      preferences: InMemoryKeyValueStore(),
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler()
    )

    await environment.bootstrap()

    // Read through the container rather than the store protocols: `RuleStore`
    // and `CategoryStore` are write-side contracts and neither offers a list.
    let context = environment.container.mainContext
    let rules = try context.fetch(FetchDescriptor<Rule>())
    let seededIDs = Set(DefaultRuleSeed.specs.map(\.id))
    let seeded = rules.filter { seededIDs.contains($0.id) }

    XCTAssertEqual(seeded.count, DefaultRuleSeed.specs.count)

    // Every seeded rule points at a category that is actually in the store, not
    // merely at an id the seed made up. This is the assertion that would catch
    // the two seeds being applied in the wrong order.
    let categoryIDs = Set(try context.fetch(FetchDescriptor<NomiCore.Category>()).map(\.id))
    for rule in seeded {
      XCTAssertTrue(categoryIDs.contains(rule.categoryID), rule.pattern)
    }
  }

  // MARK: -

  private struct Context {
    let stack: MailStack
    let coordinator: AppSyncCoordinator
    let fetcher: OrderRecordingMailFetcher
    let credentials: MemoryCredentialStore
  }

  private func makeContext(blockOnSearch: StartSignal? = nil) -> Context {
    let fetcher = OrderRecordingMailFetcher(blockOnSearch: blockOnSearch)
    let credentials = MemoryCredentialStore()
    try? credentials.save(.test)

    let stack = MailStack(
      fetcher: fetcher,
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: InMemoryKeyValueStore()
    )

    return Context(
      stack: stack,
      coordinator: AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        submitter: RecordingSubmitter()
      ),
      fetcher: fetcher,
      credentials: credentials
    )
  }
}

// MARK: - Doubles

/// A transport that records *what order* it was asked things in.
///
/// `RecordingMailFetcher` in `MailCursorPersistenceTests` counts calls by kind,
/// which answers "did a backfill happen" but cannot answer "did the connect come
/// before the search" — and that ordering is this unit's entire claim. It is
/// also in a file this unit does not own, so this is a second double rather than
/// an edit to that one.
final class OrderRecordingMailFetcher: MailFetching, @unchecked Sendable {
  enum Call: Equatable {
    case connect
    case disconnect
    case selectMailbox
    case fullRescan
    case windowedSearch
    case incrementalSearch
    case fetch

    var isSearch: Bool {
      switch self {
      case .fullRescan, .windowedSearch, .incrementalSearch: return true
      default: return false
      }
    }
  }

  private let lock = NSLock()
  private let blockOnSearch: StartSignal?
  private var recorded: [Call] = []

  init(blockOnSearch: StartSignal? = nil) {
    self.blockOnSearch = blockOnSearch
  }

  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  func connect(_ credentials: IMAPCredentials) async throws { record(.connect) }
  func disconnect() async throws { record(.disconnect) }

  func selectMailbox(_ name: String) async throws -> MailboxState {
    record(.selectMailbox)
    return MailboxState(name: name, uidValidity: 7, uidNext: 1)
  }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    record(.fullRescan)
    try await blockIfAsked()
    return []
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    record(.windowedSearch)
    try await blockIfAsked()
    return []
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    record(.incrementalSearch)
    try await blockIfAsked()
    return []
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    record(.fetch)
    return []
  }

  /// Opens the gate and then waits long enough that only cancellation ends it.
  /// Five seconds rather than minutes, so a broken guard fails the test instead
  /// of hanging CI.
  private func blockIfAsked() async throws {
    guard let blockOnSearch else { return }
    await blockOnSearch.open()
    try? await Task.sleep(nanoseconds: 5_000_000_000)
  }

  /// Through a synchronous helper, not `lock.lock()` inline: taking an `NSLock`
  /// in an async function is a warning today and an error under the Swift 6
  /// language mode. Nothing suspends in here.
  private func record(_ call: Call) {
    lock.lock()
    recorded.append(call)
    lock.unlock()
  }
}

/// `AppEnvironment` builds a `NotificationSettingsStore` and a
/// `BudgetAlertObserver`, and its default scheduler talks to
/// `UNUserNotificationCenter` — which a `swift test` binary has no business
/// reaching. Nothing here schedules anything; this exists so the composition
/// root can be constructed at all.
final class NoopNotificationScheduler: BudgetNotificationScheduling, @unchecked Sendable {
  @discardableResult
  func requestAuthorization() async throws -> Bool { false }
  func schedule(_ alert: BudgetAlert) async throws {}
}
