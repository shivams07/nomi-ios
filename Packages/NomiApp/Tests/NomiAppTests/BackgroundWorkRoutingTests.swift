import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// Findings 8 and 9: `run(_:)` read `BackgroundWork.kind` only to decide what to
/// re-schedule, and the expiration handler cancelled a task that is nil on every
/// path that reaches it.
///
/// Both are invisible to the iOS build — `BGTaskScheduler` fires these handlers,
/// nothing in CI does — so the questions are put to the two seams that exist for
/// it: `MailFetching`, which sees *which kind* of search the sync actually
/// issued, and `BackgroundWork`, whose non-iOS half stands in for `BGTask`.
///
/// The doubles are in `MailCursorPersistenceTests`; the same `MailStack` is
/// built here and handed to an `AppSyncCoordinator`.
final class BackgroundWorkRoutingTests: XCTestCase {

  // MARK: - Routing by kind

  /// The finding, stated as an assertion. A `.backfill` task used to reach
  /// `syncIfIdle()` and issue `uids(after:)` from the stored cursor — which
  /// returns nothing an interrupted backfill had not already passed, so the
  /// months it never reached stayed unfetched no matter how often iOS ran the
  /// task.
  func testABackfillTaskRunsABackfillAndNotAnIncrementalSync() async throws {
    let context = try makeContext(storedCursorAt: 20)

    try await context.stack.service.connect(.test)
    await context.coordinator.run(BackgroundWork(kind: .backfill, record: context.record))

    XCTAssertGreaterThan(context.fetcher.calls.backfillWindows, 0)
    XCTAssertEqual(context.fetcher.calls.incrementalSearches, 0)
  }

  /// The other half of the same claim: `.refresh` still does what it always did.
  /// Without this, "routes by kind" would be satisfied by a coordinator that
  /// backfills on every background task.
  func testARefreshTaskRunsAnIncrementalSync() async throws {
    let context = try makeContext(storedCursorAt: 20)

    try await context.stack.service.connect(.test)
    await context.coordinator.run(BackgroundWork(kind: .refresh, record: context.record))

    XCTAssertEqual(context.fetcher.calls.incrementalSearches, 1)
    XCTAssertEqual(context.fetcher.calls.backfillWindows, 0)
  }

  func testARefreshTaskAsksForTheNextRefresh() async throws {
    let context = try makeContext(storedCursorAt: 20)

    try await context.stack.service.connect(.test)
    await context.coordinator.run(BackgroundWork(kind: .refresh, record: context.record))

    XCTAssertEqual(context.submitter.identifiers, [AppSyncCoordinator.TaskIdentifier.refresh])
    XCTAssertEqual(context.record.recordedCompletions, [true])
  }

  /// A backfill that finished has nothing left to ask for — not another backfill,
  /// and not a refresh either, since re-scheduling on a `.backfill` task would
  /// quietly turn one interrupted scan into a permanent refresh loop.
  func testACompletedBackgroundBackfillAsksForNothingMore() async throws {
    let context = try makeContext(storedCursorAt: 20)

    try await context.stack.service.connect(.test)
    await context.coordinator.run(BackgroundWork(kind: .backfill, record: context.record))

    XCTAssertEqual(context.submitter.identifiers, [])
    XCTAssertEqual(context.record.recordedCompletions, [true])
  }

  // MARK: - Expiration

  /// Finding 9. The handler used to cancel `foregroundTask`, which is nil here —
  /// a background task runs when the app is not in the foreground, so nothing
  /// ever set it. Expiration therefore cancelled nothing and the sync ran on
  /// until iOS killed the process, which is the over-run that spends the app's
  /// scheduling budget.
  ///
  /// Two assertions, and both are needed: that the work stopped, and that the
  /// task was still answered exactly once.
  func testExpirationCancelsTheWorkInFlightAndCompletesExactlyOnce() async throws {
    let searchStarted = StartSignal()
    let context = try makeContext(storedCursorAt: 20, blockOnSearch: searchStarted)

    try await context.stack.service.connect(.test)
    let work = BackgroundWork(kind: .refresh, record: context.record)
    let run = Task { await context.coordinator.run(work) }

    await searchStarted.wait()
    context.record.expire()
    await run.value

    XCTAssertTrue(context.fetcher.sawCancellation)
    XCTAssertEqual(context.record.recordedCompletions, [false])
  }

  /// An expired backfill is an interrupted backfill, so it asks for another
  /// window rather than being dropped. This is the path that makes a six-month
  /// scan survive the OS deciding it has had long enough.
  func testAnExpiredBackfillAsksForAnotherWindow() async throws {
    let searchStarted = StartSignal()
    let context = try makeContext(storedCursorAt: 20, blockOnSearch: searchStarted)

    try await context.stack.service.connect(.test)
    let work = BackgroundWork(kind: .backfill, record: context.record)
    let run = Task { await context.coordinator.run(work) }

    await searchStarted.wait()
    context.record.expire()
    await run.value

    XCTAssertEqual(context.submitter.identifiers, [AppSyncCoordinator.TaskIdentifier.backfill])
    XCTAssertEqual(context.record.recordedCompletions, [false])
  }

  // MARK: - Backgrounding

  /// The other half of finding 8: routing `.backfill` correctly is pointless if
  /// nothing ever submits that identifier. Backgrounding is the last moment
  /// anything can be asked of iOS on an interrupted scan's behalf — after it the
  /// process is suspended and the `Task` running the backfill is simply frozen.
  func testBackgroundingDuringABackfillAsksIOSToFinishIt() async throws {
    let searchStarted = StartSignal()
    let context = try makeContext(blockOnSearch: searchStarted)

    try await context.stack.service.connect(.test)
    let backfill = Task { try? await context.stack.service.startBackfill(months: 6) }
    await searchStarted.wait()
    backfill.cancel()
    _ = await backfill.value

    await context.coordinator.didEnterBackground()

    XCTAssertTrue(
      context.submitter.identifiers.contains(AppSyncCoordinator.TaskIdentifier.backfill))
  }

  /// The control. Every backgrounding asks for a refresh; only an unfinished
  /// backfill asks for the processing task.
  func testBackgroundingWithNothingUnfinishedAsksOnlyForTheRefresh() async throws {
    let context = try makeContext()

    await context.coordinator.didEnterBackground()

    XCTAssertEqual(context.submitter.identifiers, [AppSyncCoordinator.TaskIdentifier.refresh])
  }

  // MARK: -

  private struct Context {
    let stack: MailStack
    let coordinator: AppSyncCoordinator
    let fetcher: RecordingMailFetcher
    let submitter: RecordingSubmitter
    let record: BackgroundWorkRecord
  }

  /// `storedCursorAt` seeds a cursor whose mailbox and UIDVALIDITY match the
  /// fetcher's, which is what makes an incremental sync take the `uids(after:)`
  /// branch. Without it a cold sync issues `uids(since:)` instead and the
  /// routing assertions could not tell a backfill from a first sync.
  private func makeContext(
    storedCursorAt lastSeenUID: UInt32? = nil,
    blockOnSearch: StartSignal? = nil
  ) throws -> Context {
    let preferences = InMemoryKeyValueStore()
    if let lastSeenUID {
      let cursor = MailSyncCursor(
        mailbox: "INBOX",
        uidValidity: RecordingMailFetcher.defaultUIDValidity,
        lastSeenUID: lastSeenUID
      )
      preferences.set(try JSONEncoder().encode(cursor), forKey: PreferenceKey.mailSyncCursor)
    }

    let fetcher = RecordingMailFetcher(uids: [11, 12, 42], blockOnSearch: blockOnSearch)
    let stack = makeStack(fetcher: fetcher, preferences: preferences)
    let submitter = RecordingSubmitter()

    return Context(
      stack: stack,
      coordinator: AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        submitter: submitter
      ),
      fetcher: fetcher,
      submitter: submitter,
      record: BackgroundWorkRecord()
    )
  }
}

// MARK: - Doubles

/// What was asked of `BGTaskScheduler`, which on macOS is nothing at all — the
/// class does not exist there. This is the seam that makes "an interrupted
/// backfill asks iOS to finish it" a question a test can put.
final class RecordingSubmitter: BackgroundTaskSubmitting, @unchecked Sendable {
  struct Submission: Equatable {
    let identifier: String
    let notBefore: TimeInterval
  }

  private let lock = NSLock()
  private var recorded: [Submission] = []

  var submissions: [Submission] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  var identifiers: [String] { submissions.map(\.identifier) }

  func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval) {
    lock.lock()
    recorded.append(Submission(identifier: identifier, notBefore: notBefore))
    lock.unlock()
  }
}

/// A store with nothing in it. `AppSyncCoordinator` needs an `IngestPipeline`
/// and every one of these tests reconciles an empty ledger, so the reconcile is
/// a no-op that has to succeed rather than something under test — U4 owns its
/// own tests for what it does with actual rows.
struct EmptyPipelineStore: PipelineStore {
  func rules() async throws -> [RuleSnapshot] { [] }

  func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] { [] }

  func rulePassCandidates() async throws -> [TransactionSnapshot] { [] }
  func rows(appliedRuleID: UUID) async throws -> [TransactionSnapshot] { [] }
  func duplicateGroups() async throws -> [[TransactionSnapshot]] { [] }
  func apply(_ plan: CommitPlan) async throws {}
}
