import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// I-13 Amendment 1, B5a step 2 (G4, G5). `beginErase` closes the coordinator to
/// everything that runs because of time, cancels what is already running, and
/// reopens on every path. Every await is bounded by `withTestTimeout`.
final class EraseGateTests: XCTestCase {

  /// The erase cancels the foreground and remote-change tasks, waits for the
  /// sync they were running to stop, then cancels the background requests once.
  func testBeginEraseCancelsBothTasksAndCancelsBackgroundRequestsOnce() async throws {
    let signal = StartSignal()
    let stack = try await connectedStack(fetcher: OrderRecordingMailFetcher(blockOnSearch: signal))
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(stack: stack, submitter: submitter)

    await coordinator.didBecomeActive()
    try await withTestTimeout { await signal.wait() }
    await coordinator.remoteChangeObserved()
    let foregroundTask = await coordinator.foregroundTask
    let remoteTask = await coordinator.remoteChangeTask
    let foreground = try XCTUnwrap(foregroundTask)
    let remote = try XCTUnwrap(remoteTask)

    try await withTestTimeout { try await coordinator.beginErase() }

    XCTAssertTrue(foreground.isCancelled)
    XCTAssertTrue(remote.isCancelled)
    XCTAssertEqual(submitter.cancelAllCount, 1)
    await coordinator.endErase()
  }

  /// With nothing running, the erase is immediate and still cancels the requests.
  func testBeginEraseOnAnIdleCoordinatorCancelsRequestsOnce() async throws {
    let stack = try await connectedStack(fetcher: OrderRecordingMailFetcher())
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(stack: stack, submitter: submitter)

    try await withTestTimeout { try await coordinator.beginErase() }

    XCTAssertEqual(submitter.cancelAllCount, 1)
    await coordinator.endErase()
  }

  /// While the gate is closed a sync is refused, reconcile never reaches the
  /// pipeline, and nothing is scheduled. Ending the erase reopens reconcile.
  func testWhileErasingReconcileDoesNotReachThePipelineAndEndingReopensIt() async throws {
    let store = ReconcileCountingStore()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
      submitter: EraseSubmitter(),
      store: store)

    try await withTestTimeout { try await coordinator.beginErase() }

    let attempt = await coordinator.syncIfIdle()
    XCTAssertEqual(attempt, .alreadyRunning)
    let skipped = await coordinator.reconcile()
    XCTAssertEqual(skipped, .empty)
    let reconciles = await store.duplicateGroupReads
    XCTAssertEqual(reconciles, 0, "the pipeline was not called while erasing")

    await coordinator.didBecomeActive()
    await coordinator.remoteChangeObserved()
    let foregroundTask = await coordinator.foregroundTask
    let remoteTask = await coordinator.remoteChangeTask
    XCTAssertNil(foregroundTask, "no foreground task starts while erasing")
    XCTAssertNil(remoteTask, "no remote-change task starts while erasing")

    await coordinator.endErase()
    _ = await coordinator.reconcile()
    let reopened = await store.duplicateGroupReads
    XCTAssertEqual(reopened, 1, "the gate reopened")
  }

  /// A background task that arrives while erasing completes unsuccessfully, once,
  /// and submits nothing: neither the refresh it would have re-scheduled nor the
  /// one `didEnterBackground` asks for.
  #if !os(iOS)
    func testWhileErasingBackgroundWorkCompletesUnsuccessfullyAndSchedulesNothing() async throws {
      let submitter = EraseSubmitter()
      let coordinator = makeCoordinator(
        stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
        submitter: submitter)
      try await withTestTimeout { try await coordinator.beginErase() }
      let record = BackgroundWorkRecord()

      await coordinator.run(BackgroundWork(kind: .refresh, record: record))
      await coordinator.didEnterBackground()

      XCTAssertEqual(record.recordedCompletions, [false])
      XCTAssertEqual(submitter.submissions, [], "nothing is scheduled while erasing")
    }
  #endif

  /// A sync that does not stop in time makes the erase throw `busy`, and changes
  /// nothing: the background requests stay, and the gate reopens.
  func testABusySyncTimesOutAndTheGateReopens() async throws {
    let signal = StartSignal()
    let store = ReconcileCountingStore()
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher(blockOnSearch: signal)),
      submitter: submitter,
      store: store)
    // Not a foreground or remote-change task, so the erase does not cancel it.
    let sync = Task { await coordinator.syncIfIdle() }
    try await withTestTimeout { await signal.wait() }

    do {
      try await withTestTimeout { try await coordinator.beginErase(timeout: 0.3) }
      XCTFail("a sync still running at the deadline must make the erase throw busy")
    } catch CoordinatorEraseError.busy {
      // expected
    }

    XCTAssertEqual(submitter.cancelAllCount, 0, "a busy erase leaves the background requests alone")
    _ = await coordinator.reconcile()
    let reopened = await store.duplicateGroupReads
    XCTAssertEqual(reopened, 1, "the gate reopened after busy")

    sync.cancel()
    _ = try await withTestTimeout { await sync.value }
  }

  // MARK: - Fixtures

  private func connectedStack(fetcher: OrderRecordingMailFetcher) async throws -> MailStack {
    let credentials = MemoryCredentialStore()
    try credentials.save(.test)
    let stack = MailStack(
      fetcher: fetcher,
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: InMemoryKeyValueStore()
    )
    try await stack.service.connect(.test)
    return stack
  }

  private func makeCoordinator(
    stack: MailStack,
    submitter: EraseSubmitter,
    store: any PipelineStore = EmptyPipelineStore()
  ) -> AppSyncCoordinator {
    AppSyncCoordinator(
      mail: stack,
      pipeline: IngestPipeline(store: store),
      submitter: submitter
    )
  }
}

/// A `BackgroundTaskSubmitting` that records what was submitted and how often
/// `cancelAll` ran.
private final class EraseSubmitter: BackgroundTaskSubmitting, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [String] = []
  private var cancels = 0

  var submissions: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  var cancelAllCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return cancels
  }

  func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval) {
    lock.lock()
    recorded.append(identifier)
    lock.unlock()
  }

  func cancelAll() {
    lock.lock()
    cancels += 1
    lock.unlock()
  }
}

/// Counts the reads that reach the pipeline's store, which is where a reconcile
/// lands. An empty ledger otherwise.
private actor ReconcileCountingStore: PipelineStore {
  private(set) var duplicateGroupReads = 0

  func rules() async throws -> [RuleSnapshot] { [] }

  func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] { [] }

  func duplicateGroups() async throws -> [[TransactionSnapshot]] {
    duplicateGroupReads += 1
    return []
  }

  func apply(_ plan: CommitPlan) async throws {}
  func accountFacts() async throws -> [UUID: TransferAccount] { [:] }

  func transferCandidates(
    amountMinor: Int,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] { [] }

  func applyTransferMarks(
    _ writes: [TransferPairWrite],
    updatedAt: Date
  ) async throws -> [TransferPairWrite] { [] }
}
