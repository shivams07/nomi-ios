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

    let token = try await withTestTimeout { try await coordinator.beginErase() }

    XCTAssertTrue(foreground.isCancelled)
    XCTAssertTrue(remote.isCancelled)
    XCTAssertEqual(submitter.cancelAllCount, 1)
    await coordinator.endErase(token)
  }

  /// With nothing running, the erase is immediate and still cancels the requests.
  func testBeginEraseOnAnIdleCoordinatorCancelsRequestsOnce() async throws {
    let stack = try await connectedStack(fetcher: OrderRecordingMailFetcher())
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(stack: stack, submitter: submitter)

    let token = try await withTestTimeout { try await coordinator.beginErase() }

    XCTAssertEqual(submitter.cancelAllCount, 1)
    await coordinator.endErase(token)
  }

  /// While the gate is closed a sync is refused, reconcile never reaches the
  /// pipeline, and nothing is scheduled. Ending the erase reopens reconcile.
  func testWhileErasingReconcileDoesNotReachThePipelineAndEndingReopensIt() async throws {
    let store = ReconcileCountingStore()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
      submitter: EraseSubmitter(),
      store: store)

    let token = try await withTestTimeout { try await coordinator.beginErase() }

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

    await coordinator.endErase(token)
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
      let token = try await withTestTimeout { try await coordinator.beginErase() }
      let record = BackgroundWorkRecord()

      await coordinator.run(BackgroundWork(kind: .refresh, record: record))
      await coordinator.didEnterBackground()

      XCTAssertEqual(record.recordedCompletions, [false])
      XCTAssertEqual(submitter.submissions, [], "nothing is scheduled while erasing")
      await coordinator.endErase(token)
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
      _ = try await withTestTimeout { try await coordinator.beginErase(timeout: 0.3) }
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

  // MARK: - One holder at a time (Lim's FAIL on 7372fac)

  /// A double-tap on the erase confirm: a second `beginErase` while the first is
  /// still waiting for a stuck sync throws `busy` at once, and the holder keeps the gate.
  func testASecondConcurrentBeginEraseThrowsBusyAndLeavesTheHolderInPlace() async throws {
    let signal = StartSignal()
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher(blockOnSearch: signal)),
      submitter: submitter)
    let sync = Task { await coordinator.syncIfIdle() }
    try await withTestTimeout { await signal.wait() }

    let holder = Task { try await coordinator.beginErase(timeout: 30) }
    try await waitUntilErasing(coordinator)

    do {
      _ = try await withTestTimeout { try await coordinator.beginErase(timeout: 30) }
      XCTFail("a second erase must not take the gate from the first")
    } catch CoordinatorEraseError.busy {
      // expected
    }
    let stillHeld = await coordinator.isErasing
    XCTAssertTrue(stillHeld, "the first erase still holds the gate")
    XCTAssertEqual(submitter.cancelAllCount, 0, "the first erase has not finished, so nothing is cancelled yet")

    holder.cancel()
    _ = try? await withTestTimeout { try await holder.value }
    sync.cancel()
    _ = try await withTestTimeout { await sync.value }
  }

  /// Two callers reach `beginErase` together on an idle coordinator. The actor
  /// admits one, and the other throws `busy` and changes nothing: one holder,
  /// one busy, and `cancelAll` runs once, for the holder.
  func testTwoCallersRacingForAnIdleGateGetOneHolderAndOneBusy() async throws {
    let submitter = EraseSubmitter()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
      submitter: submitter)

    async let first = attemptErase(coordinator)
    async let second = attemptErase(coordinator)
    let outcomes = await [first, second]

    let holders = outcomes.compactMap { outcome -> EraseToken? in
      if case .held(let token) = outcome { return token }
      return nil
    }
    XCTAssertEqual(holders.count, 1, "exactly one caller takes the gate")
    XCTAssertEqual(outcomes.filter { $0 == .busy }.count, 1, "the other caller is refused as busy")
    XCTAssertEqual(submitter.cancelAllCount, 1, "cancelAll ran once, for the holder")
    let closed = await coordinator.isErasing
    XCTAssertTrue(closed, "the gate is closed while the holder runs")

    for holder in holders {
      await coordinator.endErase(holder)
    }
    let reopened = await coordinator.isErasing
    XCTAssertFalse(reopened, "the holder's token reopens it")
  }

  /// The holder is the only erase that ends the gate: a second `beginErase`
  /// that was refused changes nothing, and `cancelAll` runs once, for the holder.
  func testTheGateStaysClosedUntilTheHolderEndsAndCancelsOnce() async throws {
    let submitter = EraseSubmitter()
    let store = ReconcileCountingStore()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
      submitter: submitter,
      store: store)

    let holder = try await withTestTimeout { try await coordinator.beginErase() }
    do {
      _ = try await withTestTimeout { try await coordinator.beginErase() }
      XCTFail("a second erase while one holds the gate must throw busy")
    } catch CoordinatorEraseError.busy {
      // expected
    }

    let skipped = await coordinator.reconcile()
    XCTAssertEqual(skipped, .empty, "the gate is still closed")
    let whileHeld = await store.duplicateGroupReads
    XCTAssertEqual(whileHeld, 0)
    XCTAssertEqual(submitter.cancelAllCount, 1, "cancelAll ran for the holder only, once")

    await coordinator.endErase(holder)
    _ = await coordinator.reconcile()
    let reopened = await store.duplicateGroupReads
    XCTAssertEqual(reopened, 1, "the holder ending reopens the gate")
    XCTAssertEqual(submitter.cancelAllCount, 1)
  }

  /// `endErase` with a token that is not the holder's does nothing: a stale
  /// caller cannot reopen a gate that a newer erase closed.
  func testAStaleTokenDoesNotReopenTheGate() async throws {
    let store = ReconcileCountingStore()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher()),
      submitter: EraseSubmitter(),
      store: store)

    let first = try await withTestTimeout { try await coordinator.beginErase() }
    await coordinator.endErase(first)
    let second = try await withTestTimeout { try await coordinator.beginErase() }

    await coordinator.endErase(first)
    let afterStale = await coordinator.isErasing
    XCTAssertTrue(afterStale, "the stale token left the gate closed")
    let skipped = await coordinator.reconcile()
    XCTAssertEqual(skipped, .empty)
    let whileHeld = await store.duplicateGroupReads
    XCTAssertEqual(whileHeld, 0)

    await coordinator.endErase(second)
    let afterHolder = await coordinator.isErasing
    XCTAssertFalse(afterHolder, "the holder's token reopens it")
  }

  /// M7. A caller cancelled while `beginErase` waits must reopen the gate and see
  /// `CancellationError`, not `busy`, and the next erase must be able to start.
  func testACallerCancelledMidWaitReopensTheGateAndThrowsCancellation() async throws {
    let signal = StartSignal()
    let store = ReconcileCountingStore()
    let coordinator = makeCoordinator(
      stack: try await connectedStack(fetcher: OrderRecordingMailFetcher(blockOnSearch: signal)),
      submitter: EraseSubmitter(),
      store: store)
    let sync = Task { await coordinator.syncIfIdle() }
    try await withTestTimeout { await signal.wait() }

    let erase = Task { try await coordinator.beginErase(timeout: 30) }
    try await waitUntilErasing(coordinator)
    erase.cancel()

    do {
      _ = try await withTestTimeout { try await erase.value }
      XCTFail("a cancelled erase must throw")
    } catch is CancellationError {
      // expected
    }
    let afterCancel = await coordinator.isErasing
    XCTAssertFalse(afterCancel, "the cancelled caller reopened the gate")
    _ = await coordinator.reconcile()
    let reopened = await store.duplicateGroupReads
    XCTAssertEqual(reopened, 1, "reconcile reaches the pipeline again")

    // The stuck sync is still running, and a new erase would wait for it. Stop it first.
    sync.cancel()
    _ = try await withTestTimeout { await sync.value }

    let next = try await withTestTimeout { try await coordinator.beginErase() }
    await coordinator.endErase(next)
  }

  private enum EraseAttempt: Equatable {
    case held(EraseToken)
    case busy
    case other
  }

  private func attemptErase(_ coordinator: AppSyncCoordinator) async -> EraseAttempt {
    do {
      return .held(try await coordinator.beginErase())
    } catch CoordinatorEraseError.busy {
      return .busy
    } catch {
      return .other
    }
  }

  /// Polls until the gate is closed, so a test can rely on a holder being in place.
  private func waitUntilErasing(_ coordinator: AppSyncCoordinator) async throws {
    try await withTestTimeout {
      while !(await coordinator.isErasing) {
        try await Task.sleep(nanoseconds: 5_000_000)
      }
    }
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
