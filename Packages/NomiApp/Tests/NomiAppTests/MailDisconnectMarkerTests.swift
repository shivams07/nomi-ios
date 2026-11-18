import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// The unfinished-backfill marker and a disconnect that returns late.
///
/// `CursorPersistingMailConnectionService.disconnect` clears the marker after its
/// upstream disconnect returns. The erase path abandons that disconnect after
/// 10 s, so it can return after a new backfill has set the marker. The marker
/// then belongs to a session the disconnect does not belong to, and the late
/// clear would drop it.
final class MailDisconnectMarkerTests: XCTestCase {

  /// The bug. A disconnect is parked upstream, a backfill starts and sets the
  /// marker, and then the disconnect returns. The marker must still be set while
  /// that backfill runs.
  ///
  /// Fails on the old code: the late disconnect clears the marker the backfill
  /// set, so a backfill that is running reads as finished.
  func testAStaleDisconnectDoesNotClearTheMarkerOfABackfillStartedAfterIt() async throws {
    let upstream = ParkingUpstream()
    let preferences = InMemoryKeyValueStore()
    let wrapper = CursorPersistingMailConnectionService(
      upstream: upstream,
      engine: MailSyncEngine(fetcher: RecordingMailFetcher(uids: []), pipeline: SilentPipeline()),
      preferences: preferences)

    let disconnect = Task { try await wrapper.disconnect() }
    for await _ in upstream.disconnectBegan { break }

    let backfill = Task { try await wrapper.startBackfill(months: 6) }
    for await _ in upstream.backfillBegan { break }
    XCTAssertTrue(
      preferences.bool(forKey: PreferenceKey.mailBackfillUnfinished),
      "setup: the backfill that started after the disconnect set the marker")

    await upstream.disconnectGate.open()
    _ = try await disconnect.value

    XCTAssertTrue(
      preferences.bool(forKey: PreferenceKey.mailBackfillUnfinished),
      "a disconnect that returned late cleared the marker of the backfill running now")

    await upstream.backfillGate.open()
    _ = await backfill.result
  }

  /// The path that must keep working: a disconnect with no backfill started since
  /// it began clears the marker, as it always has.
  func testADisconnectWithNoLaterBackfillClearsTheMarker() async throws {
    let upstream = ParkingUpstream()
    let preferences = InMemoryKeyValueStore()
    preferences.set(true, forKey: PreferenceKey.mailBackfillUnfinished)
    let wrapper = CursorPersistingMailConnectionService(
      upstream: upstream,
      engine: MailSyncEngine(fetcher: RecordingMailFetcher(uids: []), pipeline: SilentPipeline()),
      preferences: preferences)

    await upstream.disconnectGate.open()
    try await wrapper.disconnect()

    XCTAssertFalse(preferences.bool(forKey: PreferenceKey.mailBackfillUnfinished))
  }
}

/// A connection whose `disconnect` and `startBackfill` wait for the test. The
/// backfill ends by throwing `CancellationError` once released, which leaves the
/// marker as it was set.
private final class ParkingUpstream: MailConnectionService, @unchecked Sendable {
  let state: AsyncStream<MailConnectionState> = AsyncStream { $0.finish() }
  let backfillProgress: AsyncStream<BackfillProgress> = AsyncStream { $0.finish() }

  let disconnectGate = MarkerTestGate()
  let backfillGate = MarkerTestGate()
  let disconnectBegan: AsyncStream<Void>
  let backfillBegan: AsyncStream<Void>
  private let disconnectSink: AsyncStream<Void>.Continuation
  private let backfillSink: AsyncStream<Void>.Continuation

  init() {
    var disconnectContinuation: AsyncStream<Void>.Continuation!
    disconnectBegan = AsyncStream(bufferingPolicy: .unbounded) { disconnectContinuation = $0 }
    disconnectSink = disconnectContinuation
    var backfillContinuation: AsyncStream<Void>.Continuation!
    backfillBegan = AsyncStream(bufferingPolicy: .unbounded) { backfillContinuation = $0 }
    backfillSink = backfillContinuation
  }

  func connect(_ credentials: IMAPCredentials) async throws {}

  func disconnect() async throws {
    disconnectSink.yield(())
    await disconnectGate.wait()
  }

  func syncNow() async throws -> SyncSummary {
    throw CancellationError()
  }

  func startBackfill(months: Int) async throws -> SyncSummary {
    backfillSink.yield(())
    await backfillGate.wait()
    throw CancellationError()
  }
}

/// Holds callers in `wait` until `open`. Once open, every later `wait` returns at once.
private actor MarkerTestGate {
  private var isOpen = false
  private var parked: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { parked.append($0) }
  }

  func open() {
    isOpen = true
    let waiting = parked
    parked = []
    for continuation in waiting { continuation.resume() }
  }
}
