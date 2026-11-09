import Combine
import Foundation
import NomiCore
import XCTest

@testable import NomiApp

/// U9b. **Nothing here constructs a `CKContainer`**, and that is the point of
/// the probe being a protocol: doing so in a process without the iCloud
/// entitlement raises an uncatchable ObjC exception that kills the test
/// process outright (CI run 33994342474, signal 5, no failing assertion).
/// `CKAccountProbe` itself is therefore not exercised here — it cannot be,
/// under `swift test`, and pretending otherwise is how that run happened.
final class StorageModeMonitorTests: XCTestCase {

  /// A probe whose answers the test controls, and whose change stream the test
  /// drives by hand.
  private final class FakeProbe: CloudKitAccountProbing, @unchecked Sendable {
    private let lock = NSLock()
    private var _reason: SyncPauseReason?
    private var _probeCount = 0
    private var _streamOpened = false
    private var continuation: AsyncStream<Void>.Continuation?

    init(reason: SyncPauseReason?) { _reason = reason }

    var probeCount: Int { lock.withLock { _probeCount } }

    /// True once `run()` has subscribed to the account-change stream, which it
    /// does after its first refresh. Lets a test wait for that point exactly.
    var streamOpened: Bool { lock.withLock { _streamOpened } }

    func setReason(_ reason: SyncPauseReason?) { lock.withLock { _reason = reason } }

    func emitAccountChange() { continuation?.yield(()) }
    func finish() { continuation?.finish() }

    func pauseReason() async -> SyncPauseReason? {
      lock.withLock {
        _probeCount += 1
        return _reason
      }
    }

    func accountChanges() -> AsyncStream<Void> {
      AsyncStream { continuation in
        self.continuation = continuation
        self.lock.withLock { self._streamOpened = true }
      }
    }
  }

  // MARK: - The resolver

  /// The whole reason `.localOnly` is a separate case: this process is not on
  /// a CloudKit store, so no account status can make it sync. Reporting it as
  /// paused would promise a resumption that cannot happen without a relaunch.
  func testALocalOnlyLaunchStaysLocalOnlyWhateverTheAccountSays() {
    let constructed = StorageMode.localOnly(reason: "boom")

    XCTAssertEqual(
      StorageModeResolver.resolve(constructed: constructed, account: nil), constructed)
    XCTAssertEqual(
      StorageModeResolver.resolve(constructed: constructed, account: .noAccount), constructed)
  }

  func testACloudKitLaunchWithNoAccountIsPausedWithThatReason() {
    XCTAssertEqual(
      StorageModeResolver.resolve(constructed: .cloudKit, account: .noAccount),
      .cloudKitPaused(.noAccount))
    XCTAssertEqual(
      StorageModeResolver.resolve(constructed: .cloudKit, account: .restricted),
      .cloudKitPaused(.restricted))
  }

  /// Resolution has to be able to run *backwards* too — a paused app whose
  /// account comes back must return to `.cloudKit`, not stay stuck.
  func testAnAvailableAccountResolvesBackToCloudKit() {
    XCTAssertEqual(
      StorageModeResolver.resolve(constructed: .cloudKitPaused(.noAccount), account: nil),
      .cloudKit)
    XCTAssertEqual(StorageModeResolver.resolve(constructed: .cloudKit, account: nil), .cloudKit)
  }

  // MARK: - The monitor

  /// Before the first probe returns, the monitor must report what the launch
  /// actually constructed. Starting at `.cloudKit` would put "On" on screen
  /// for a launch that had already fallen back.
  @MainActor
  func testTheModeStartsAtTheConstructedValueNotAtSyncing() {
    let monitor = StorageModeMonitor(
      constructed: .localOnly(reason: "boom"), probe: FakeProbe(reason: nil))

    XCTAssertEqual(monitor.mode, .localOnly(reason: "boom"))
    XCTAssertFalse(monitor.mode.isSyncing)
  }

  @MainActor
  func testOneRefreshPausesACloudKitLaunchWithNoAccount() async {
    let monitor = StorageModeMonitor(constructed: .cloudKit, probe: FakeProbe(reason: .noAccount))

    await monitor.refresh()

    XCTAssertEqual(monitor.mode, .cloudKitPaused(.noAccount))
    XCTAssertFalse(monitor.mode.isSyncing, "a paused container is not syncing")
  }

  // MARK: - SIM1: a local-only launch never asks the probe

  /// `CKAccountProbe.pauseReason()` builds a `CKContainer`, which traps an
  /// unsigned simulator build. A local-only monitor must not ask it at all, and
  /// two refreshes must leave the probe untouched.
  @MainActor
  func testALocalOnlyMonitorNeverAsksTheProbe() async {
    let probe = FakeProbe(reason: .noAccount)
    let monitor = StorageModeMonitor(constructed: .localOnly(reason: "boom"), probe: probe)

    await monitor.refresh()
    await monitor.refresh()

    XCTAssertEqual(probe.probeCount, 0, "a local-only process must not reach CloudKit")
    XCTAssertEqual(monitor.mode, .localOnly(reason: "boom"))
  }

  /// Skipping the probe is only invisible if the mode never depended on it.
  /// Every answer, including none, must leave a local-only launch unchanged.
  @MainActor
  func testALocalOnlyModeIsTheSameWhateverTheProbeWouldHaveSaid() async {
    let constructed = StorageMode.localOnly(reason: "boom")
    let answers: [SyncPauseReason?] = [
      nil, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine("x"),
    ]
    for answer in answers {
      let monitor = StorageModeMonitor(constructed: constructed, probe: FakeProbe(reason: answer))
      await monitor.refresh()
      XCTAssertEqual(monitor.mode, constructed, "probe answer \(String(describing: answer))")
    }
  }

  /// `run()` on a local-only launch still subscribes to account changes (a
  /// notification, not a container), but the first refresh and every later one
  /// leave the probe alone.
  @MainActor
  func testRunOnALocalOnlyLaunchSubscribesButNeverProbes() async {
    let probe = FakeProbe(reason: .noAccount)
    let monitor = StorageModeMonitor(constructed: .localOnly(reason: "boom"), probe: probe)

    let running = Task { await monitor.run() }
    await untilTrue { probe.streamOpened }
    probe.finish()
    await running.value

    XCTAssertEqual(probe.probeCount, 0)
    XCTAssertEqual(monitor.mode, .localOnly(reason: "boom"))
  }

  /// The CloudKit path is unchanged: every refresh still asks the probe once.
  @MainActor
  func testACloudKitMonitorAsksTheProbeOnEveryRefresh() async {
    let probe = FakeProbe(reason: nil)
    let monitor = StorageModeMonitor(constructed: .cloudKit, probe: probe)

    await monitor.refresh()
    await monitor.refresh()

    XCTAssertEqual(probe.probeCount, 2)
  }

  /// The behaviour the unit exists for: the app is running, already showing
  /// "On", and the account goes away underneath it.
  @MainActor
  func testAnEmittedAccountChangeReResolvesTheMode() async {
    let probe = FakeProbe(reason: nil)
    let monitor = StorageModeMonitor(constructed: .cloudKit, probe: probe)

    let running = Task { await monitor.run() }
    await untilTrue { monitor.mode == .cloudKit && probe.probeCount >= 1 }

    probe.setReason(.noAccount)
    probe.emitAccountChange()
    await untilTrue { monitor.mode == .cloudKitPaused(.noAccount) }

    // And back again, because signing in has to work as well as signing out.
    probe.setReason(nil)
    probe.emitAccountChange()
    await untilTrue { monitor.mode == .cloudKit }

    probe.finish()
    await running.value
  }

  /// `refresh()` runs on every foreground. If it published unconditionally,
  /// each one would re-render the whole tree to say what the row already says.
  @MainActor
  func testAnUnchangedAnswerDoesNotPublish() async {
    let monitor = StorageModeMonitor(constructed: .cloudKit, probe: FakeProbe(reason: .noAccount))
    var published = 0
    let cancellable = monitor.$mode.sink { _ in published += 1 }
    defer { cancellable.cancel() }

    XCTAssertEqual(published, 1, "sink receives the current value on subscribe")

    await monitor.refresh()
    XCTAssertEqual(published, 2, "the first probe is a real change")

    await monitor.refresh()
    await monitor.refresh()
    XCTAssertEqual(published, 2, "the same answer twice more must not publish")
  }

  /// Polls rather than sleeps a fixed interval: the monitor's work hops
  /// through an `AsyncStream` and the main actor, so there is no single
  /// deterministic point to wait for, and a fixed sleep would be either flaky
  /// or slow.
  @MainActor
  private func untilTrue(
    _ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line
  ) async {
    for _ in 0..<200 {
      if condition() { return }
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTFail("condition never became true", file: file, line: line)
  }
}
