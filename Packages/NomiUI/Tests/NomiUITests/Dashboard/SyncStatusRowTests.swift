import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class SyncStatusRowTests: XCTestCase {
  func testConnectedWithLastSyncShowsRelativeTime() {
    let now = Date(timeIntervalSince1970: 10_000)
    let lastSync = Date(timeIntervalSince1970: 9_700)
    let text = SyncStatusRow.statusText(for: .connected(address: "a@b.com", lastSync: lastSync), now: now)
    XCTAssertTrue(text.hasPrefix("Synced"))
  }

  func testConnectedWithNoLastSyncIsNotYetSynced() {
    let text = SyncStatusRow.statusText(for: .connected(address: "a@b.com", lastSync: nil))
    XCTAssertEqual(text, "Connected — not yet synced")
  }

  func testDisconnectedReadsAsAFactNotAnError() {
    let text = SyncStatusRow.statusText(for: .disconnected)
    XCTAssertEqual(text, "Mail not connected")
    XCTAssertFalse(text.lowercased().contains("error"))
    XCTAssertFalse(text.contains("!"))
  }

  func testConnectingShowsInProgressState() {
    XCTAssertEqual(SyncStatusRow.statusText(for: .connecting), "Connecting…")
  }

  func testFailedStateHasNoAlarmingPunctuation() {
    let text = SyncStatusRow.statusText(for: .failed(.connectionFailed))
    XCTAssertFalse(text.contains("!"))
  }
}
