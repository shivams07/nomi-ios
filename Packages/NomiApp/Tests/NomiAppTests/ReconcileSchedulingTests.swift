import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// W1-2 (M10). Reconcile was a full-table scan on every foreground and every
/// remote-change notification. These pin when it runs now.
///
/// Time is a `FakeClock`: `now` for the ten-minute foreground gate, and `sleep`
/// for the two-second debounce, which only returns when the test advances past
/// it. No test here waits on a real clock.
///
/// Reconciles are counted at the reference-data seam, which
/// `AppSyncCoordinator.reconcile()` calls exactly once per reconcile. The mail
/// doubles are `MailCursorPersistenceTests`'; `EmptyPipelineStore` and
/// `RecordingSubmitter` are `BackgroundWorkRoutingTests'`.
@MainActor
final class ReconcileSchedulingTests: XCTestCase {

  // MARK: - Remote change

  func testTwoRemoteChangesAHundredMillisecondsApartRunOneReconcile() async throws {
    let clock = FakeClock()
    let harness = try makeHarness(clock: clock)

    await harness.coordinator.remoteChangeObserved()
    await clock.waitForSleeps(1)
    clock.advance(by: 0.1)
    await harness.coordinator.remoteChangeObserved()
    await clock.waitForSleeps(2)

    XCTAssertEqual(clock.pendingSleeps, 1, "the second notification cancels the first one's wait")

    // Past the moment the first reconcile was due, short of the second's.
    clock.advance(by: 1.95)
    await Task.yield()
    XCTAssertEqual(harness.referenceData.runs, 0)

    // Two seconds after the *last* notification.
    clock.advance(by: 0.1)
    let pending = await harness.coordinator.remoteChangeTask
    await pending?.value

    XCTAssertEqual(harness.referenceData.runs, 1)
  }

  // MARK: - Foreground

  func testASecondForegroundInsideTenMinutesSyncsWithoutReconciling() async throws {
    let clock = FakeClock()
    let harness = try makeHarness(clock: clock)
    try await harness.stack.service.connect(.test)

    await harness.coordinator.didBecomeActive()
    await foregroundWork(of: harness.coordinator)
    clock.advance(by: 9 * 60)
    await harness.coordinator.didBecomeActive()
    await foregroundWork(of: harness.coordinator)

    XCTAssertEqual(harness.referenceData.runs, 1, "the second foreground is nine minutes after the first reconcile")
    XCTAssertEqual(harness.fetcher.calls.incrementalSearches, 2, "and both foregrounds synced")
  }

  /// The control. Without it, a coordinator that reconciled once and never again
  /// would pass the test above.
  func testAForegroundTenMinutesAfterTheLastReconcileReconcilesAgain() async throws {
    let clock = FakeClock()
    let harness = try makeHarness(clock: clock)
    try await harness.stack.service.connect(.test)

    await harness.coordinator.didBecomeActive()
    await foregroundWork(of: harness.coordinator)
    clock.advance(by: 10 * 60)
    await harness.coordinator.didBecomeActive()
    await foregroundWork(of: harness.coordinator)

    XCTAssertEqual(harness.referenceData.runs, 2)
    XCTAssertEqual(harness.fetcher.calls.incrementalSearches, 2)
  }

  // MARK: -

  private struct Harness {
    let stack: MailStack
    let coordinator: AppSyncCoordinator
    let fetcher: RecordingMailFetcher
    let referenceData: CountingReferenceData
  }

  private func foregroundWork(of coordinator: AppSyncCoordinator) async {
    let task = await coordinator.foregroundTask
    await task?.value
  }

  /// A stored cursor matching the fetcher, so every sync is an incremental
  /// `uids(after:)` and counts as exactly one search.
  private func makeHarness(clock: FakeClock) throws -> Harness {
    let preferences = InMemoryKeyValueStore()
    let cursor = MailSyncCursor(
      mailbox: "INBOX",
      uidValidity: RecordingMailFetcher.defaultUIDValidity,
      lastSeenUID: 20
    )
    preferences.set(try JSONEncoder().encode(cursor), forKey: PreferenceKey.mailSyncCursor)

    let fetcher = RecordingMailFetcher(uids: [11, 12, 42])
    let stack = makeStack(fetcher: fetcher, preferences: preferences)
    let referenceData = CountingReferenceData()

    return Harness(
      stack: stack,
      coordinator: AppSyncCoordinator(
        mail: stack,
        pipeline: IngestPipeline(store: EmptyPipelineStore()),
        referenceData: referenceData,
        submitter: RecordingSubmitter(),
        now: { clock.now },
        sleep: { try await clock.sleep($0) }
      ),
      fetcher: fetcher,
      referenceData: referenceData
    )
  }
}

// MARK: - Doubles

/// Counts calls at the seam `AppSyncCoordinator.reconcile()` reaches once per
/// reconcile.
@MainActor
final class CountingReferenceData: ReferenceDataReconciling {
  private(set) var runs = 0

  func run() throws -> Int {
    runs += 1
    return 0
  }
}

/// A clock that moves only when told to.
///
/// `sleep` parks the caller until `advance` carries the clock past its
/// deadline, and throws `CancellationError` the moment its task is cancelled —
/// which is the property the debounce test is about.
final class FakeClock: @unchecked Sendable {
  private struct Sleeper {
    let id: Int
    let deadline: TimeInterval
    let continuation: CheckedContinuation<Void, Error>
  }

  private let lock = NSLock()
  private let origin = Date(timeIntervalSince1970: 1_789_000_000)
  private var elapsed: TimeInterval = 0
  private var sleepers: [Sleeper] = []
  private var registered = 0
  private var nextID = 0

  var now: Date { locked { origin.addingTimeInterval(elapsed) } }

  /// Sleeps still waiting for their deadline.
  var pendingSleeps: Int { locked { sleepers.count } }

  /// Sleeps that have ever started waiting.
  var registeredSleeps: Int { locked { registered } }

  func sleep(_ seconds: TimeInterval) async throws {
    let id = locked { () -> Int in
      nextID += 1
      return nextID
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        register(id: id, seconds: seconds, continuation: continuation)
      }
    } onCancel: {
      cancel(id: id)
    }
  }

  func advance(by seconds: TimeInterval) {
    let due = locked { () -> [Sleeper] in
      elapsed += seconds
      let due = sleepers.filter { $0.deadline <= elapsed }
      sleepers.removeAll { $0.deadline <= elapsed }
      return due
    }
    for sleeper in due {
      sleeper.continuation.resume()
    }
  }

  /// A task created by the coordinator starts on its own schedule, so a test
  /// that advances the clock before the task has begun waiting would advance
  /// past nothing. Five seconds of polling, then a failure rather than a hang.
  func waitForSleeps(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<5_000 {
      if registeredSleeps >= count { return }
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTFail("expected \(count) sleeps to have started, saw \(registeredSleeps)", file: file, line: line)
  }

  // Synchronous helpers: an `NSLock` taken directly in an async function is a
  // warning today and an error under the Swift 6 language mode.

  private func register(id: Int, seconds: TimeInterval, continuation: CheckedContinuation<Void, Error>) {
    lock.lock()
    // Cancelled before it could wait: `onCancel` has already run and found
    // nothing to cancel, so this is the only place left to say so.
    if Task.isCancelled {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    sleepers.append(Sleeper(id: id, deadline: elapsed + seconds, continuation: continuation))
    registered += 1
    lock.unlock()
  }

  private func cancel(id: Int) {
    let cancelled = locked { () -> Sleeper? in
      guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
      return sleepers.remove(at: index)
    }
    cancelled?.continuation.resume(throwing: CancellationError())
  }

  private func locked<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }
}
