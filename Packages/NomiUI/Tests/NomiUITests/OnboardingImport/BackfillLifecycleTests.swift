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
    return Self.backfillSummary
  }

  func recordedMethods() -> [String] { calledMethods }
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
}
