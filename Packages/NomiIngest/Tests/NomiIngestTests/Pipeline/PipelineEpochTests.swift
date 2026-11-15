import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// I-13 Amendment 1, B5a step 1 (G5). Erase runs inside the pipeline's exclusive
/// section and bumps an epoch. A batch fetched before the erase, and queued on
/// the lock behind it, must throw and write nothing. A batch that starts after
/// the erase runs normally.
///
/// Every await here goes through `withTestTimeout`, so a hung pipeline fails the
/// test rather than the run.
final class PipelineEpochTests: XCTestCase {

  /// The order the spec describes: the ingest is queued before the erase is
  /// granted the lock, so it captured the epoch the erase has not yet bumped.
  /// A holder keeps the lock while the erase and then the ingest queue behind it.
  /// Release: the erase runs and bumps, and the ingest is refused.
  ///
  /// The two settles are real pauses, not observable events. If the erase or the
  /// ingest reaches the lock late, the order flips: the ingest is granted first and
  /// writes, and the test fails red on `applyCount`, never green by accident.
  func testAnIngestQueuedBeforeTheEraseThrowsAndWritesNothing() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    let hold = PipelineHold()
    let marker = EraseMarker()

    let holder = Task {
      await pipeline.runExclusiveForErase {
        await hold.enter()
      }
    }
    try await withTestTimeout { await hold.waitUntilEntered() }

    let erase = Task {
      await pipeline.runExclusiveForErase {
        await marker.run()
      }
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    let queued = Task { try await pipeline.ingest([Fixture.draft()]) }
    try await Task.sleep(nanoseconds: 200_000_000)

    await hold.release()
    try await withTestTimeout { await holder.value }
    try await withTestTimeout { await erase.value }

    do {
      _ = try await withTestTimeout { try await queued.value }
      XCTFail("a batch queued before the erase's bump must not write after it")
    } catch is CancellationError {
      // expected
    }

    let eraseRan = await marker.ran
    let applies = await store.applyCount
    let rows = await store.rowCount
    XCTAssertTrue(eraseRan, "the erase's body ran in its turn")
    XCTAssertEqual(applies, 0, "nothing was committed")
    XCTAssertEqual(rows, 0, "no row was written")
  }

  func testAnIngestStartedAfterTheEraseRunsNormally() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    try await withTestTimeout { await pipeline.runExclusiveForErase {} }

    let result = try await withTestTimeout { try await pipeline.ingest([Fixture.draft()]) }

    XCTAssertEqual(result.created, 1)
    let applies = await store.applyCount
    XCTAssertEqual(applies, 1)
  }

  func testAReconcileQueuedBehindTheEraseIsSkipped() async throws {
    let phone = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-20 10:00")
    let pad = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-21 11:00")
    let store = FakePipelineStore(rows: [phone, pad])
    let pipeline = await Fixture.pipeline(store: store)
    let hold = PipelineHold()

    // Same order as the ingest test: holder, then the erase, then the reconcile.
    let holder = Task {
      await pipeline.runExclusiveForErase {
        await hold.enter()
      }
    }
    try await withTestTimeout { await hold.waitUntilEntered() }

    let erase = Task {
      await pipeline.runExclusiveForErase {}
    }
    try await Task.sleep(nanoseconds: 200_000_000)

    let queued = Task { try await pipeline.reconcile() }
    try await Task.sleep(nanoseconds: 200_000_000)

    await hold.release()
    try await withTestTimeout { await holder.value }
    try await withTestTimeout { await erase.value }

    do {
      _ = try await withTestTimeout { try await queued.value }
      XCTFail("a reconcile fetched before the erase must not write after it")
    } catch is CancellationError {
      // expected
    }

    let rows = await store.rowCount
    let applies = await store.applyCount
    XCTAssertEqual(rows, 2, "both duplicate rows are still there")
    XCTAssertEqual(applies, 0, "the collapse was not committed")
  }
}

/// Records that the erase's body ran.
private actor EraseMarker {
  private(set) var ran = false

  func run() {
    ran = true
  }
}

/// Holds the lock inside its exclusive section until the test releases it, and
/// tells the test when the section has been entered.
private actor PipelineHold {
  private var entered = false
  private var released = false
  private var enterWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func enter() async {
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
