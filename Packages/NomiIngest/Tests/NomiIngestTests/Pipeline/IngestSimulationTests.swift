import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// I-12 Amendment 1, B4b step 2. `simulate` runs the ingest loop without writing:
/// it reports what `ingest` reports over the same drafts, leaves the store alone,
/// and gives way to an erase between chunks (B5a's epoch).
///
/// Every await goes through `withTestTimeout`, so a hung pipeline fails the test
/// rather than the run.
final class IngestSimulationTests: XCTestCase {

  /// Sixty drafts. Draft 0 and draft 59 are the same line, so the repeat crosses
  /// the pipeline's 50-row chunk boundary: draft 59 is the tenth draft of chunk two.
  private static func drafts() -> [TransactionDraft] {
    (0..<60).map { index in
      let repeated = index == 0 || index == 59
      return Fixture.draft(
        description: repeated ? "DUP ROW" : "ROW \(index)",
        amountMinor: repeated ? 45_000 : 10_000 + index,
        externalID: repeated ? "REFDUP" : "REF\(index)"
      )
    }
  }

  // MARK: - Agreement with ingest

  /// Simulate on one fresh store reports what chunked ingest reports on another
  /// identical fresh store, the way the file import commits: one `ingest` per
  /// 50 drafts. Created, merged, the created draft indexes and the repeat count
  /// must all match, with the draft indexes counted over the whole file.
  func testSimulateCountsEqualIngestOnIdenticalFreshStores() async throws {
    let drafts = Self.drafts()

    let simulateStore = FakePipelineStore()
    let simulatePipeline = await Fixture.pipeline(store: simulateStore)
    let simulated = try await withTestTimeout { try await simulatePipeline.simulate(drafts) }

    let commitStore = FakePipelineStore()
    let commitPipeline = await Fixture.pipeline(store: commitStore)
    var committedCreated = 0
    var committedMerged = 0
    var committedCreatedIndexes: [Int] = []
    var createdIDs: Set<UUID> = []
    var committedRepeats = 0
    var offset = 0
    for batch in drafts.slices(of: MailSyncEngine.fetchBatchSize) {
      let result = try await withTestTimeout { try await commitPipeline.ingest(batch) }
      committedCreated += result.created
      committedMerged += result.merged
      committedCreatedIndexes += result.createdDraftIndexes.map { $0 + offset }
      createdIDs.formUnion(result.createdIDs)
      committedRepeats += result.mergeTargetIDs.filter { createdIDs.contains($0) }.count
      offset += batch.count
    }

    let simulatedIDs = Set(simulated.createdIDs)
    let simulatedRepeats = simulated.mergeTargetIDs.filter { simulatedIDs.contains($0) }.count
    XCTAssertEqual(simulated.created, committedCreated, "created")
    XCTAssertEqual(simulated.merged, committedMerged, "merged")
    XCTAssertEqual(simulated.createdDraftIndexes, committedCreatedIndexes, "created draft indexes")
    XCTAssertEqual(simulatedRepeats, committedRepeats, "repeats in file")
    XCTAssertEqual(simulated.created, 59, "fixture: sixty drafts, one repeat")
    XCTAssertEqual(simulatedRepeats, 1, "fixture: the repeat is counted once")
  }

  /// Ingest reports the ids it creates and the row each merged draft folds into,
  /// and the draft index of each created row. `[A, B, A']` creates draft 0 and
  /// draft 1; `[A, A', B]` creates draft 0 and draft 2. The indexes tell them apart.
  func testIngestReportsCreatedIDsMergeTargetsAndDraftIndexes() async throws {
    let a = Fixture.draft(description: "SWIGGY", amountMinor: 45_900, externalID: "A")
    let b = Fixture.draft(description: "ZOMATO", amountMinor: 12_000, externalID: "B")

    let firstPipeline = await Fixture.pipeline(store: FakePipelineStore())
    let first = try await withTestTimeout { try await firstPipeline.ingest([a, b, a]) }
    XCTAssertEqual(first.createdDraftIndexes, [0, 1], "A B A: the repeat is draft 2")
    XCTAssertEqual(first.createdIDs.count, 2)
    XCTAssertEqual(first.mergeTargetIDs, Array(first.createdIDs.prefix(1)), "the repeat folds into A's row")

    let secondPipeline = await Fixture.pipeline(store: FakePipelineStore())
    let second = try await withTestTimeout { try await secondPipeline.ingest([a, a, b]) }
    XCTAssertEqual(second.createdDraftIndexes, [0, 2], "A A B: the repeat is draft 1")
    XCTAssertEqual(second.createdIDs.count, 2)
    XCTAssertEqual(second.mergeTargetIDs, Array(second.createdIDs.prefix(1)), "the repeat folds into A's row")
  }

  // MARK: - Writes

  /// A simulation reads the store and never writes it: no apply, no transfer
  /// mark, no observer call, and the stored row it matches is left as it was.
  func testSimulateLeavesTheStoreUnchanged() async throws {
    // Draft 5 of the fixture is already stored, so the simulation matches it.
    let stored = Fixture.row(
      from: Fixture.draft(description: "ROW 5", amountMinor: 10_005, externalID: "REF5"),
      createdAt: "2026-08-20 10:00")
    let store = FakePipelineStore(rows: [stored])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)
    let before = await store.allRows

    let result = try await withTestTimeout { try await pipeline.simulate(Self.drafts()) }

    let after = await store.allRows
    let applies = await store.applyCount
    let rows = await store.rowCount
    let transferWrites = await store.appliedTransferWrites
    XCTAssertEqual(result.merged, 2, "draft 5 matches the stored row, and draft 59 repeats draft 0")
    XCTAssertEqual(after, before, "the simulation changes no stored row")
    XCTAssertEqual(applies, 0, "the simulation never calls apply")
    XCTAssertEqual(rows, 1, "the simulation creates no row")
    XCTAssertTrue(transferWrites.isEmpty, "the simulation never marks transfers")
    XCTAssertEqual(observer.callCount, 0, "the simulation never notifies the observer")
  }

  // MARK: - Erase between chunks

  /// An erase that is queued behind a simulation's first chunk gets the lock
  /// before the second chunk, bumps the epoch, and the second chunk refuses to
  /// run. Nothing is written. The erase is queued while the first chunk holds the
  /// lock (the gate), and the simulation yields after each chunk so the erase is
  /// granted before the next chunk's epoch check.
  func testAnEraseDuringTheSecondChunkThrowsCancellation() async throws {
    let inner = FakePipelineStore()
    let gate = SimulationGate()
    let pipeline = IngestPipeline(
      store: GatedStore(inner: inner, gate: gate),
      calendar: Fixture.calendar, transferCalendar: Fixture.calendar, now: Fixture.clock)
    let drafts = Self.drafts()

    let simulation = Task { try await pipeline.simulate(drafts) }
    try await withTestTimeout { await gate.waitUntilEntered() }

    // The erase queues behind the first chunk, which holds the lock at the gate.
    let erase = Task { await pipeline.runExclusiveForErase {} }
    try await Task.sleep(nanoseconds: 200_000_000)

    await gate.release()
    try await withTestTimeout { await erase.value }

    do {
      _ = try await withTestTimeout { try await simulation.value }
      XCTFail("a simulation whose next chunk was fetched before the erase must throw")
    } catch is CancellationError {
      // Expected.
    }

    let rows = await inner.rowCount
    let applies = await inner.applyCount
    XCTAssertEqual(rows, 0, "nothing was written")
    XCTAssertEqual(applies, 0, "nothing was committed")
  }
}

// MARK: - Gate

/// Holds the simulation inside its first `rules()` read, which happens under the
/// lock, until the test releases it, and says when the hold has been reached.
private actor SimulationGate {
  private var entered = false
  private var released = false
  private var enterWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func pass() async {
    entered = true
    let waiting = enterWaiters
    enterWaiters = []
    waiting.forEach { $0.resume() }
    if released { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilEntered() async {
    if entered { return }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      enterWaiters.append(continuation)
    }
  }

  func release() {
    released = true
    let waiting = releaseWaiters
    releaseWaiters = []
    waiting.forEach { $0.resume() }
  }
}

/// `FakePipelineStore` with its first `rules()` read held at the gate. The first
/// chunk reads rules under the lock, so the simulation is parked holding the lock.
private actor GatedStore: PipelineStore {
  private let inner: FakePipelineStore
  private let gate: SimulationGate
  private var rulesReads = 0

  init(inner: FakePipelineStore, gate: SimulationGate) {
    self.inner = inner
    self.gate = gate
  }

  func rules() async throws -> [RuleSnapshot] {
    rulesReads += 1
    if rulesReads == 1 { await gate.pass() }
    return try await inner.rules()
  }

  func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    try await inner.mergeCandidates(amountMinor: amountMinor, directionRaw: directionRaw, dateRange: dateRange)
  }

  func duplicateGroups() async throws -> [[TransactionSnapshot]] {
    try await inner.duplicateGroups()
  }

  func apply(_ plan: CommitPlan) async throws {
    try await inner.apply(plan)
  }

  func accountFacts() async throws -> [UUID: TransferAccount] {
    try await inner.accountFacts()
  }

  func transferCandidates(
    amountMinor: Int,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    try await inner.transferCandidates(amountMinor: amountMinor, dateRange: dateRange)
  }

  func applyTransferMarks(
    _ writes: [TransferPairWrite],
    updatedAt: Date
  ) async throws -> [TransferPairWrite] {
    try await inner.applyTransferMarks(writes, updatedAt: updatedAt)
  }
}
