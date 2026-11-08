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

  // MARK: - Future or sub-second lastSync reads "just now"

  /// A fixed clock, so the relative phrase never depends on `Date()`.
  private let syncNow = Date(timeIntervalSince1970: 1_000_000)

  private func syncText(lastSyncOffset: TimeInterval) -> String {
    SyncStatusRow.statusText(
      for: .connected(address: "a@b.com", lastSync: syncNow.addingTimeInterval(lastSyncOffset)),
      now: syncNow)
  }

  /// The formatter's own phrase for an offset, so the cases below say what the
  /// row must show without restating en_IN wording.
  private func relativePhrase(lastSyncOffset: TimeInterval) -> String {
    "Synced " + NomiFormatters.relativeTime.localizedString(
      for: syncNow.addingTimeInterval(lastSyncOffset), relativeTo: syncNow)
  }

  func testSyncedExactlyNowReadsJustNow() {
    XCTAssertEqual(syncText(lastSyncOffset: 0), "Synced just now")
  }

  func testSyncedHalfASecondAgoReadsJustNow() {
    XCTAssertEqual(syncText(lastSyncOffset: -0.5), "Synced just now")
  }

  func testSyncedOneSecondAgoKeepsTheRelativeForm() {
    XCTAssertEqual(syncText(lastSyncOffset: -1), relativePhrase(lastSyncOffset: -1))
    XCTAssertNotEqual(syncText(lastSyncOffset: -1), "Synced just now")
  }

  func testSyncedAnHourAheadReadsJustNow() {
    XCTAssertEqual(syncText(lastSyncOffset: 3_600), "Synced just now")
    XCTAssertFalse(syncText(lastSyncOffset: 3_600).contains("in "))
  }

  func testSyncedFiftyNineSecondsAgoKeepsTheRelativeForm() {
    XCTAssertEqual(syncText(lastSyncOffset: -59), relativePhrase(lastSyncOffset: -59))
    XCTAssertNotEqual(syncText(lastSyncOffset: -59), "Synced just now")
  }

  func testSyncedSixtyOneSecondsAgoKeepsTheRelativeForm() {
    XCTAssertEqual(syncText(lastSyncOffset: -61), relativePhrase(lastSyncOffset: -61))
    XCTAssertNotEqual(syncText(lastSyncOffset: -61), "Synced just now")
  }

  func testSyncedThreeDaysAgoReadsThreeDaysAgo() {
    XCTAssertEqual(syncText(lastSyncOffset: -3 * 86_400), "Synced 3 days ago")
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
