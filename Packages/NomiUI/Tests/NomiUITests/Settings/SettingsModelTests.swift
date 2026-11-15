import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `SettingsModel` with a spy service (T2a). Each scan's Task is awaited under
/// `withTestTimeout`, and nothing sleeps. The kill list is in each test's comment.
@MainActor
final class SettingsModelTests: XCTestCase {
  private var suiteName = ""
  private var defaults: UserDefaults!

  /// An error whose `localizedDescription` is the framework's, with the type name in it.
  private struct E: Error {}

  override func setUp() {
    super.setUp()
    suiteName = "T2.Settings.\(UUID())"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    defaults?.removePersistentDomain(forName: suiteName)
    defaults = nil
    super.tearDown()
  }

  private func awaitTask(_ task: Task<Void, Never>) async throws {
    try await withTestTimeout { await task.value }
  }

  private func notice() -> StoreRecoveryNotice {
    StoreRecoveryNotice(movedAt: Date(timeIntervalSince1970: 1_794_648_612), fileName: "default-20261114T093012.store")
  }

  /// The alert copy never shows `localizedDescription`. Kills T2-M12.
  func testRescanFailureNeverShowsTheErrorDescription() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.syncNow, with: E())
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    try await awaitTask(model.rescan())

    let text = try XCTUnwrap(model.rescanError)
    XCTAssertEqual(text, "Couldn’t finish the scan. Check your connection and try again.")
    XCTAssertFalse(text.contains("E()"))
    XCTAssertFalse(text.contains("operation"))
  }

  /// The same copy for the six-month scan. Kills T2-M13.
  func testScanRecentFailureNeverShowsTheErrorDescription() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.startBackfill(months: 6), with: E())
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    try await awaitTask(model.scanRecent())

    let text = try XCTUnwrap(model.rescanError)
    XCTAssertEqual(text, "Couldn’t finish the scan. Check your connection and try again.")
    XCTAssertFalse(text.contains("E()"))
    XCTAssertFalse(text.contains("operation"))
  }

  /// A cancelled scan is not a failure the user is told about.
  func testCancelledScanRaisesNoAlert() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.syncNow, with: CancellationError())
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    try await awaitTask(model.rescan())

    XCTAssertNil(model.rescanError)
  }

  func testMailErrorUsesMailCopy() async throws {
    let spy = MailConnectionSpy()
    spy.fail(.syncNow, with: MailError.authenticationFailed)
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    try await awaitTask(model.rescan())

    XCTAssertEqual(model.rescanError, MailErrorMessage.text(for: .authenticationFailed))
  }

  /// Force re-scan calls `syncNow` and nothing else, and keeps the summary. The
  /// loading flag is on as soon as the call returns, and off once it ends.
  func testRescanCallsSyncNowOnlyAndKeepsTheSummary() async throws {
    let spy = MailConnectionSpy()
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    let task = model.rescan()
    XCTAssertTrue(model.isRescanning)

    try await awaitTask(task)

    XCTAssertEqual(spy.calls, [.syncNow])
    XCTAssertEqual(model.lastSyncSummary?.scanned, 3)
    XCTAssertFalse(model.isRescanning)
  }

  /// "Scan last 6 months" asks the service for six months, and nothing else.
  func testScanRecentAsksForSixMonths() async throws {
    let spy = MailConnectionSpy()
    let model = SettingsModel(service: spy, storeRecovery: nil, recoveryDefaults: defaults)

    try await awaitTask(model.scanRecent())

    XCTAssertEqual(spy.calls, [.startBackfill(months: 6)])
    XCTAssertFalse(model.isScanningRecent)
  }

  /// Dismiss forgets the record in the suite and hides the row. Kills T2-M14.
  func testDismissClearsTheRecordAndHidesTheRow() throws {
    StoreRecoveryRecord.save(notice(), to: defaults)
    let model = SettingsModel(service: MailConnectionSpy(), storeRecovery: notice(), recoveryDefaults: defaults)
    XCTAssertNotNil(model.storeRecovery)

    model.dismissStoreRecovery()

    XCTAssertNil(StoreRecoveryRecord.load(from: defaults))
    XCTAssertNil(model.storeRecovery)
  }

  /// The recovery row has no chevron, and says what the notice says. Kills T2-M15.
  func testRecoveryRowHasNoChevron() {
    let row = SettingsScreen.storeRecoveryRow(notice())

    XCTAssertFalse(row.showsChevron)
    XCTAssertEqual(row.title, "Saved data couldn’t be opened")
    XCTAssertEqual(row.message, StoreRecoveryDisplay.caption(for: notice()))
  }
}
