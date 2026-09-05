import Foundation
import NomiCore
import XCTest
@testable import NomiUI

private actor SpyMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  private(set) var calledMethods: [String] = []

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
    return SyncSummary(scanned: 5, created: 1, merged: 0, flagged: 0, packMatched: 1, heuristicMatched: 0, unmatchedSenders: [])
  }

  func startBackfill(months: Int) async throws {
    calledMethods.append("startBackfill")
  }

  func recordedMethods() -> [String] { calledMethods }
}

final class SettingsLogicTests: XCTestCase {
  func testToggleIsOffWhenPermissionDeniedEvenIfSettingIsOn() {
    let settings = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    XCTAssertFalse(NotificationToggleDisplay.isOn(settings: settings, permissionDenied: true))
  }

  func testToggleReflectsSettingWhenPermissionGranted() {
    let on = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    let off = NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.9)
    XCTAssertTrue(NotificationToggleDisplay.isOn(settings: on, permissionDenied: false))
    XCTAssertFalse(NotificationToggleDisplay.isOn(settings: off, permissionDenied: false))
  }

  func testExplanationRowShowsOnlyWhenPermissionDenied() {
    XCTAssertTrue(NotificationToggleDisplay.showsPermissionExplanation(permissionDenied: true))
    XCTAssertFalse(NotificationToggleDisplay.showsPermissionExplanation(permissionDenied: false))
  }

  func testRescanCallsSyncNowOnly() async throws {
    let spy = SpyMailConnectionService()
    _ = try await SettingsActions.rescan(using: spy)
    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, ["syncNow"])
  }

  func testRescanNeverCallsDisconnectOrConnect() async throws {
    let spy = SpyMailConnectionService()
    _ = try await SettingsActions.rescan(using: spy)
    let calls = await spy.recordedMethods()
    XCTAssertFalse(calls.contains("disconnect"))
    XCTAssertFalse(calls.contains("connect"))
  }

  func testRescanReturnsTheSyncSummaryRatherThanDiscardingIt() async throws {
    let spy = SpyMailConnectionService()
    let summary = try await SettingsActions.rescan(using: spy)
    XCTAssertEqual(summary.scanned, 5)
  }

  func testUnmatchedSenderRowsNamesDomainAndCount() {
    let rows = UnmatchedSenderDisplay.rows(for: [UnmatchedSender(domain: "chase.com", count: 3)])
    XCTAssertEqual(rows, ["chase.com — 3"])
  }

  func testUnmatchedSenderRowsIsEmptyForNoneUnmatchedRatherThanAnEmptySection() {
    XCTAssertEqual(UnmatchedSenderDisplay.rows(for: []), [])
  }

  func testUnmatchedSenderRowsNeverEmitsAnAddress() {
    let rows = UnmatchedSenderDisplay.rows(for: [
      UnmatchedSender(domain: "chase.com", count: 3),
      UnmatchedSender(domain: "boa.com", count: 1),
    ])
    XCTAssertFalse(rows.contains { $0.contains("@") })
  }

  // MARK: - B11: the storage mode is visible to the user, not just to Xcode

  func testSyncingReadsAsOnWithNoCaption() {
    XCTAssertEqual(StorageModeDisplay.text(for: .cloudKit), "On")
    XCTAssertNil(
      StorageModeDisplay.caption(for: .cloudKit),
      "one line when there is nothing to explain")
  }

  /// The row a user in the fallback state sees. Before this they saw nothing
  /// at all: the app worked and simply never appeared on their other device.
  func testTheLocalFallbackSaysSoAndSaysWhy() {
    let mode = StorageMode.localOnly(reason: "CKError: Not entitled")

    XCTAssertEqual(StorageModeDisplay.text(for: mode), "Off — this device only")

    let caption = StorageModeDisplay.caption(for: mode)
    XCTAssertNotNil(caption)
    XCTAssertTrue(
      caption?.contains("CKError: Not entitled") == true,
      "the underlying reason is carried through so a report is actionable")
    XCTAssertTrue(
      caption?.contains("safe on this device") == true,
      "the first thing to say is that nothing was lost")
  }

  func testTheModeAccessorsAgreeWithWhatIsDisplayed() {
    XCTAssertTrue(StorageMode.cloudKit.isSyncing)
    XCTAssertNil(StorageMode.cloudKit.reason)
    XCTAssertFalse(StorageMode.localOnly(reason: "x").isSyncing)
    XCTAssertEqual(StorageMode.localOnly(reason: "x").reason, "x")
  }
}
