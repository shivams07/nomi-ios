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
/// it. Two tests here wait on a real clock, because they go through
/// `AppEnvironment`'s production sleep:
/// `testASettledRemoteChangeIncrementsTheInsightsGeneration` and
/// `testASettledRemoteChangeDoesNotNotifyThePostCommitObserver`.
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

  // MARK: - Remote change settled (WR-1, G3)

  /// Two notifications inside the debounce window: one settled reconcile, one
  /// hook call. Not settled one second before the last notification's deadline.
  func testRemoteChangeSettledHookRunsOnceAfterDebouncedReconcile() async throws {
    let clock = FakeClock()
    let settled = SettledCounter()
    let harness = try makeHarness(clock: clock, hook: { settled.record() })
    settled.referenceData = harness.referenceData

    await harness.coordinator.remoteChangeObserved()
    await clock.waitForSleeps(1)
    clock.advance(by: 0.1)
    await harness.coordinator.remoteChangeObserved()
    await clock.waitForSleeps(2)

    clock.advance(by: 1.95)
    await Task.yield()
    XCTAssertEqual(settled.count, 0, "nothing has settled before two seconds after the last notification")

    clock.advance(by: 0.1)
    let pending = await harness.coordinator.remoteChangeTask
    await pending?.value

    XCTAssertEqual(harness.referenceData.runs, 1)
    XCTAssertEqual(settled.count, 1, "two notifications, one settled reconcile, one hook call")
    XCTAssertEqual(settled.reconcileCountsAtCall, [1], "the hook runs after the reconcile, not before it")
  }

  /// The import changed rows whether or not the reconcile then removed a
  /// duplicate, so the hook runs when the reconcile removes nothing. The
  /// reference-data seam here returns zero removals and the pipeline store is
  /// empty, so this reconcile collapses nothing.
  func testRemoteChangeSettledHookRunsWhenTheReconcileRemovesNothing() async throws {
    let clock = FakeClock()
    let settled = SettledCounter()
    let harness = try makeHarness(clock: clock, hook: { settled.record() })
    settled.referenceData = harness.referenceData

    await harness.coordinator.remoteChangeObserved()
    await clock.waitForSleeps(1)
    clock.advance(by: 2)
    let pending = await harness.coordinator.remoteChangeTask
    await pending?.value

    XCTAssertEqual(harness.referenceData.runs, 1, "the reconcile ran")
    XCTAssertEqual(settled.count, 1, "and the hook ran after it, though it removed nothing")
    XCTAssertEqual(
      settled.reconcileCountsAtCall, [1],
      "the reconcile had already run when the hook fired: a hook moved ahead of it would see 0")
  }

  /// No remote change, no hook. The foreground reconcile does run here, so the
  /// zero is not a reconcile that never happened.
  func testForegroundReconcileDoesNotRunTheRemoteChangeHook() async throws {
    let clock = FakeClock()
    let settled = SettledCounter()
    let harness = try makeHarness(clock: clock, hook: { settled.record() })
    try await harness.stack.service.connect(.test)

    await harness.coordinator.didBecomeActive()
    await foregroundWork(of: harness.coordinator)

    XCTAssertEqual(harness.referenceData.runs, 1, "the foreground reconciled")
    XCTAssertEqual(settled.count, 0, "with no remote change there is nothing to invalidate")
  }

  /// The wiring, not the coordinator: `AppEnvironment` hands the coordinator
  /// `cache.invalidate()`, and the generation is what `RootView` republishes to
  /// the screens that read through the cache.
  ///
  /// This one goes through the production two-second sleep, because the
  /// environment does not take an injected one. It is the only test in this
  /// file that waits on a real clock, and it is here for that reason.
  func testASettledRemoteChangeIncrementsTheInsightsGeneration() async throws {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let environment = AppEnvironment(
      container: stack.container,
      preferences: InMemoryKeyValueStore(),
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler()
    )
    let before = environment.cache.generation

    await environment.sync.remoteChangeObserved()
    let pending = await environment.sync.remoteChangeTask
    await pending?.value

    // Exactly one, on an empty store: the reconcile collapses nothing, so the
    // only invalidation is the hook's.
    XCTAssertEqual(environment.cache.generation, before + 1)
  }

  /// Pins the audit's "budget alerts do not fire on a remote import". The
  /// environment's budget observer is replaced on its own coordinator by a
  /// counter, so any post-commit call a settled remote change makes is seen.
  ///
  /// This does not kill the M2 mutant (wiring `coordinator.didWrite()` in place
  /// of `cache.invalidate()`). A no-argument `didWrite()` never reaches the
  /// observer, so M2 passes here. The test catches the change that would make
  /// M2 dangerous: a non-empty category set passed to `didWrite` on this path.
  ///
  /// Like the test above, this goes through the production two-second sleep.
  func testASettledRemoteChangeDoesNotNotifyThePostCommitObserver() async throws {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let environment = AppEnvironment(
      container: stack.container,
      preferences: InMemoryKeyValueStore(),
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler()
    )
    let observer = CountingPostCommitObserver()
    environment.coordinator.setObserver(observer)
    let before = environment.cache.generation

    await environment.sync.remoteChangeObserved()
    let pending = await environment.sync.remoteChangeTask
    await pending?.value

    // The settled path really ran, so zero observer calls is not a no-op.
    XCTAssertEqual(environment.cache.generation, before + 1)
    XCTAssertEqual(observer.count, 0, "a remote import must not run the budget observer")
  }

  // MARK: -

  private struct Harness {
    let stack: MailStack
    let coordinator: AppSyncCoordinator
    let fetcher: RecordingMailFetcher
    let referenceData: CountingReferenceData
  }

  /// Keeps each `InMemoryStack` alive for the test. A `ModelContext` does not
  /// keep its container alive, and a dropped container traps SwiftData mid-test.
  private var stacks: [InMemoryStack] = []

  private func foregroundWork(of coordinator: AppSyncCoordinator) async {
    let task = await coordinator.foregroundTask
    await task?.value
  }

  /// A stored cursor matching the fetcher, so every sync is an incremental
  /// `uids(after:)` and counts as exactly one search.
  private func makeHarness(
    clock: FakeClock,
    hook: (@MainActor @Sendable () -> Void)? = nil
  ) throws -> Harness {
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
        sleep: { try await clock.sleep($0) },
        onRemoteChangeSettled: hook
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

/// Counts calls to the remote-change settled hook, and what the reconcile
/// counter read when each call happened. A reference type, because a
/// `@Sendable` closure cannot mutate a captured `var`.
///
/// `referenceData` is set by the test after the harness exists, because the
/// hook has to be handed to the coordinator before the harness can be built.
@MainActor
final class SettledCounter {
  private(set) var count = 0
  private(set) var reconcileCountsAtCall: [Int] = []
  var referenceData: CountingReferenceData?

  func record() {
    count += 1
    reconcileCountsAtCall.append(referenceData?.runs ?? -1)
  }
}

/// Counts post-commit observer calls. `didCommit` is async, so the count sits
/// behind a lock taken in a synchronous helper.
final class CountingPostCommitObserver: PostCommitObserver, @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return calls
  }

  func didCommit(affectedCategoryIDs: Set<UUID>) async {
    record()
  }

  private func record() {
    lock.lock()
    calls += 1
    lock.unlock()
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
