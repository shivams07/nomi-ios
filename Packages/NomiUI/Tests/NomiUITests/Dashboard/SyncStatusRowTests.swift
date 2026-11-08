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

  // MARK: - HM2 Home banner

  /// Only states that need attention get the banner. Connected has nothing to ask.
  func testConnectedHasNoAttentionRow() {
    XCTAssertNil(SyncStatusRow.attention(for: .connected(address: "a@b.com", lastSync: nil)))
  }

  func testDisconnectedBannerSaysWhatToDo() {
    let attention = SyncStatusRow.attention(for: .disconnected)
    XCTAssertEqual(attention?.title, "Mail disconnected")
    XCTAssertEqual(attention?.message, "Connect again to keep your numbers current.")
  }

  func testFailedBannerTitleIsTheReachFailure() {
    let attention = SyncStatusRow.attention(for: .failed(.connectionFailed))
    XCTAssertEqual(attention?.title, "Couldn’t reach your mail")
    XCTAssertEqual(attention?.message, "Check your connection, then try again.")
  }

  func testConnectingBannerHasNoMessage() {
    let attention = SyncStatusRow.attention(for: .connecting)
    XCTAssertEqual(attention?.title, "Connecting…")
    XCTAssertNil(attention?.message)
  }

  func testEveryFailureHasAMessageWithoutAnAlarmMark() {
    let errors: [MailError] = [.authenticationFailed, .connectionFailed, .unknown("socket reset 54")]
    for error in errors {
      let message = SyncStatusRow.failureMessage(for: error)
      XCTAssertFalse(message.isEmpty)
      XCTAssertFalse(message.contains("!"))
      XCTAssertFalse(message.contains("socket reset"), "an unknown error's raw text must not reach the user")
    }
  }
}
