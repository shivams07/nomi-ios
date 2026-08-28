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
}
