import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// Returns a deliberately different summary from each method, so *which* call
/// produced the screen's completion card is visible in the value itself and not
/// only in the call log. A pass-through test against one shared summary would
/// be green either way.
private actor BackfillSpyMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  private(set) var calledMethods: [String] = []
  /// "start" and "end" for each `startBackfill`, in order. Read by the Resume test.
  private(set) var scanEvents: [String] = []
  private var holdsNextScan = false
  private var failsNextScan = false
  private var released = false
  private var windDown: CheckedContinuation<Void, Never>?

  static let backfillSummary = SyncSummary(
    scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 80,
    heuristicMatched: 11,
    unmatchedSenders: [UnmatchedSender(domain: "bandhanbank.in", count: 3)])
  static let syncSummary = SyncSummary(
    scanned: 7, created: 1, merged: 0, flagged: 0, packMatched: 1,
    heuristicMatched: 0, unmatchedSenders: [])

  init() {
    state = AsyncStream { _ in }
    backfillProgress = AsyncStream { _ in }
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    calledMethods.append("connect")
  }

  func disconnect() async throws {
    calledMethods.append("disconnect")
  }

  @discardableResult
  func syncNow() async throws -> SyncSummary {
    calledMethods.append("syncNow")
    return Self.syncSummary
  }

  @discardableResult
  func startBackfill(months: Int) async throws -> SyncSummary {
    calledMethods.append("startBackfill")
    let holds = holdsNextScan
    holdsNextScan = false
    scanEvents.append("start")
    if failsNextScan {
      failsNextScan = false
      throw URLError(.notConnectedToInternet)
    }
    if holds {
      do {
        // A 5 s cap, so a broken test cannot hang the run. Only cancellation ends it sooner.
        try await Task.sleep(nanoseconds: 5_000_000_000)
      } catch {
        // Like the real service, a cancelled scan keeps going until its next
        // batch boundary. The test decides when that boundary comes.
        if !released {
          await withCheckedContinuation { windDown = $0 }
        }
        scanEvents.append("end")
        throw error
      }
    }
    scanEvents.append("end")
    return Self.backfillSummary
  }

  /// The next `startBackfill` runs until it is cancelled, then winds down only
  /// when `releaseWindDown()` is called.
  func holdNextScan() { holdsNextScan = true }

  /// The next `startBackfill` throws as a dropped connection would.
  func failNextScan() { failsNextScan = true }

  func releaseWindDown() {
    released = true
    windDown?.resume()
    windDown = nil
  }

  func recordedMethods() -> [String] { calledMethods }
}

/// Thrown when a polled condition does not become true in time.
private struct ConditionNeverHeld: Error {}

/// Polls `condition` every 10 ms for up to 3 s.

private func waitUntil(_ condition: @escaping () async -> Bool) async throws {
  for _ in 0..<300 {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  throw ConditionNeverHeld()
}

/// Whether `task` finishes within 5 s. The bound keeps a broken chain from
/// hanging the test run. Not a task group: a group waits for a child that ignores
/// cancellation, so a stuck scan held the run for ever (T1). `withTestTimeout` returns at
/// the deadline and abandons the await.
private func finishes(_ task: Task<Void, Never>) async -> Bool {
  (try? await withTestTimeout(seconds: 5) { await task.value; return true }) ?? false
}

final class BackfillLifecycleTests: XCTestCase {

  func testAppearingForTheFirstTimeStarts() {
    XCTAssertTrue(BackfillLifecycle.shouldStartOnAppear(phase: .notStarted))
  }

  // The regression `onDisappear`'s cancel was covering for: without it, a
  // still-running scan must not be started a second time just because the
  // screen was left and come back to with no Cancel tap in between.
  func testLeavingMidScanAndReturningWithNoCancelDoesNotRestart() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .running))
  }

  func testReturningToACancelledScanDoesNotAutoResume() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .cancelled))
  }

  func testReturningToACompletedScanDoesNotRestart() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .completed))
  }

  /// A failed scan waits for Retry. Coming back to the screen must not start
  /// a fresh scan the user did not ask for.
  func testReturningToAFailedScanDoesNotAutoRetry() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .failed))
  }

  // MARK: - The completion summary's provenance

  /// The screen renders what the scan returned. `unmatchedSenders` is the
  /// tell-tale: `syncNow`'s summary has none, so a completion card built from a
  /// second sync could not show a discovered domain.
  func testTheCompletionSummaryIsTheBackfillsAndNotASecondSyncs() async throws {
    let spy = BackfillSpyMailConnectionService()

    let summary = try await BackfillActions.scan(using: spy, months: 6)

    XCTAssertEqual(summary.scanned, 1200)
    XCTAssertEqual(summary.created, 91)
    XCTAssertEqual(summary.unmatchedSenders.map(\.domain), ["bandhanbank.in"])
    XCTAssertNotEqual(
      summary.scanned, BackfillSpyMailConnectionService.syncSummary.scanned,
      "that is syncNow's summary — the completion card is reporting the wrong run")
  }

  /// The regression this unit exists to prevent: the screen used to end its
  /// progress loop with a full `syncNow()` purely to obtain something to
  /// render, re-fetching and re-ingesting the entire mailbox it had just
  /// scanned.
  func testTheScanNeverCallsSyncNow() async throws {
    let spy = BackfillSpyMailConnectionService()

    _ = try await BackfillActions.scan(using: spy, months: 6)

    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, ["startBackfill"])
    XCTAssertFalse(
      calls.contains("syncNow"),
      "a second full sync just to get a summary the backfill already returned")
  }

  // MARK: - Resume waits for the scan it cancelled

  /// Cancel, then Resume, while the cancelled scan is still winding down. The
  /// resumed scan must wait for it, so the service never sees two scans at once.
  func testResumeWaitsForThePreviousScan() async throws {
    let spy = BackfillSpyMailConnectionService()
    await spy.holdNextScan()

    // Start the first scan, then Cancel it, as `BackfillScreen` does.
    let first = BackfillSchedule.next(after: nil) {
      _ = try? await spy.startBackfill(months: 6)
    }
    try await waitUntil { await spy.scanEvents.contains("start") }
    first.cancel()

    // Resume. Its scan is chained after the first, which has not finished.
    let resumed = BackfillSchedule.next(after: first) {
      _ = try? await spy.startBackfill(months: 6)
    }

    // Give a second start every chance to begin while the first still winds down.
    try await Task.sleep(nanoseconds: 300_000_000)
    let beforeWindDown = await spy.scanEvents
    XCTAssertEqual(
      beforeWindDown, ["start"],
      "Resume began a second scan while the cancelled one was still winding down")

    await spy.releaseWindDown()
    let finished = await finishes(resumed)
    XCTAssertTrue(finished, "the resumed scan never finished")
    let events = await spy.scanEvents
    XCTAssertEqual(
      events, ["start", "end", "start", "end"],
      "the scans overlapped or the resumed one never ran after the first ended")
  }

  // MARK: - BackfillRun: the screen's lifecycle outside the view (T2b)

  /// Resume, while the cancelled scan still winds down, waits for it. Kills T2-M16: with
  /// `task = Task { await scan() }` the resumed scan starts at once.
  @MainActor
  func testRunResumeWaitsForTheCancelledScan() async throws {
    let spy = BackfillSpyMailConnectionService()
    await spy.holdNextScan()
    let run = BackfillRun(service: spy, months: 6)

    run.appear()
    try await waitUntil { await spy.scanEvents == ["start"] }
    _ = run.perform(.cancel)
    _ = run.perform(.resume)

    // Give a second start every chance to begin while the first still winds down.
    try await Task.sleep(nanoseconds: 200_000_000)
    let beforeWindDown = await spy.scanEvents
    XCTAssertEqual(
      beforeWindDown, ["start"],
      "Resume began a second scan while the cancelled one was still winding down")

    await spy.releaseWindDown()
    let resumed = try XCTUnwrap(run.task)
    let resumedFinished = await finishes(resumed)
    XCTAssertTrue(resumedFinished, "the resumed scan never finished")
    let events = await spy.scanEvents
    XCTAssertEqual(
      events, ["start", "end", "start", "end"],
      "the resumed scan did not run after the cancelled one ended")
  }

  /// Appearing again after the scan completed does not scan again. Kills T2-M17: without the
  /// `shouldStartOnAppear` guard, the second appear records a second `startBackfill`. Two appears
  /// in a row would not catch it: the first task is cancelled before it scans.
  @MainActor
  func testRunAppearStartsOnce() async throws {
    let spy = BackfillSpyMailConnectionService()
    let run = BackfillRun(service: spy, months: 6)

    run.appear()
    let first = try XCTUnwrap(run.task)
    let firstFinished = await finishes(first)
    XCTAssertTrue(firstFinished, "the first scan never finished")
    XCTAssertEqual(run.phase, .completed)

    run.appear()
    let second = try XCTUnwrap(run.task)
    let secondFinished = await finishes(second)
    XCTAssertTrue(secondFinished, "the second appear's task never finished")
    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, ["startBackfill"], "appearing on a completed scan scanned again")
  }

  /// A cancel followed by a thrown error is a pause, not a failure. Kills T2-M18: without
  /// `isCancelled = true` the phase stays `.running`, because the cancelled task's own
  /// `isCancelled` hides the error.
  @MainActor
  func testRunCancelThenThrowIsAPause() async throws {
    let spy = BackfillSpyMailConnectionService()
    await spy.holdNextScan()
    let run = BackfillRun(service: spy, months: 6)

    run.appear()
    try await waitUntil { await spy.scanEvents == ["start"] }
    _ = run.perform(.cancel)
    XCTAssertEqual(run.phase, .cancelled, "Cancel did not pause the scan at once")

    await spy.releaseWindDown()
    let scan = try XCTUnwrap(run.task)
    let scanFinished = await finishes(scan)
    XCTAssertTrue(scanFinished, "the cancelled scan never wound down")
    XCTAssertEqual(run.phase, .cancelled)
    XCTAssertFalse(run.didFail, "a cancel the user asked for was reported as a failure")
  }

  /// A thrown scan fails, clears the task, and Retry starts a new one.
  @MainActor
  func testRunFailureThenRetry() async throws {
    let spy = BackfillSpyMailConnectionService()
    await spy.failNextScan()
    let run = BackfillRun(service: spy, months: 6)

    run.appear()
    let failed = try XCTUnwrap(run.task)
    let failedFinished = await finishes(failed)
    XCTAssertTrue(failedFinished, "the failing scan never finished")
    XCTAssertEqual(run.phase, .failed)
    XCTAssertNil(run.task)

    _ = run.perform(.retry)
    let retried = try XCTUnwrap(run.task)
    let retriedFinished = await finishes(retried)
    XCTAssertTrue(retriedFinished, "the retried scan never finished")
    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, ["startBackfill", "startBackfill"])
    XCTAssertEqual(run.phase, .completed)
  }

  /// The completion card shows the scan's own summary, as the scan returned it.
  @MainActor
  func testRunCompletesWithTheScansOwnSummary() async throws {
    let spy = BackfillSpyMailConnectionService()
    let run = BackfillRun(service: spy, months: 6)

    run.appear()
    let scan = try XCTUnwrap(run.task)
    let scanFinished = await finishes(scan)
    XCTAssertTrue(scanFinished, "the scan never finished")
    XCTAssertEqual(run.phase, .completed)
    XCTAssertEqual(run.completionSummary?.created, 91)
  }

  /// Done leaves onboarding and does not touch the service.
  @MainActor
  func testRunDoneFinishesWithoutCallingTheService() async {
    let spy = BackfillSpyMailConnectionService()
    let run = BackfillRun(service: spy, months: 6)

    XCTAssertEqual(run.perform(.done), .finish)
    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, [])
  }
}
