import Foundation
import NomiCore
import XCTest
@testable import NomiUI

private actor SpyMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  private(set) var calledMethods: [String] = []
  private(set) var backfillMonths: [Int] = []

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

  @discardableResult
  func startBackfill(months: Int) async throws -> SyncSummary {
    calledMethods.append("startBackfill")
    backfillMonths.append(months)
    return SyncSummary(scanned: 180, created: 12, merged: 0, flagged: 2, packMatched: 10, heuristicMatched: 2, unmatchedSenders: [])
  }

  func recordedMethods() -> [String] { calledMethods }
  func recordedBackfillMonths() -> [Int] { backfillMonths }
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

  // MARK: - M7: "Scan last 6 months"

  func testScanRecentCallsStartBackfillWithSixMonthsOnly() async throws {
    let spy = SpyMailConnectionService()
    _ = try await SettingsActions.scanRecent(using: spy)
    let calls = await spy.recordedMethods()
    XCTAssertEqual(calls, ["startBackfill"])
  }

  func testScanRecentPassesSixMonths() async throws {
    let spy = SpyMailConnectionService()
    _ = try await SettingsActions.scanRecent(using: spy)
    let months = await spy.recordedBackfillMonths()
    XCTAssertEqual(months, [6])
  }

  func testScanRecentReturnsTheBackfillSummaryRatherThanDiscardingIt() async throws {
    let spy = SpyMailConnectionService()
    let summary = try await SettingsActions.scanRecent(using: spy)
    XCTAssertEqual(summary.scanned, 180)
    XCTAssertEqual(summary.created, 12)
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

  // MARK: - U9b: paused is its own state, and reads differently from failed

  /// Each paused reason gets its own words. Collapsing them into one "Off"
  /// would be the same failure B11 fixed, one level down: the user is told
  /// sync is off and still has no idea what to do about it.
  func testEachPausedReasonHasItsOwnText() {
    let texts = [
      StorageModeDisplay.text(for: .cloudKitPaused(.noAccount)),
      StorageModeDisplay.text(for: .cloudKitPaused(.restricted)),
      StorageModeDisplay.text(for: .cloudKitPaused(.temporarilyUnavailable)),
      StorageModeDisplay.text(for: .cloudKitPaused(.couldNotDetermine("x"))),
      StorageModeDisplay.text(for: .localOnly(reason: "x")),
      StorageModeDisplay.text(for: .cloudKit),
    ]

    XCTAssertEqual(Set(texts).count, texts.count, "no two states may read the same")
    XCTAssertEqual(
      StorageModeDisplay.text(for: .cloudKitPaused(.noAccount)), "Off — not signed in to iCloud")
    XCTAssertEqual(
      StorageModeDisplay.text(for: .cloudKitPaused(.restricted)), "Off — iCloud restricted")
  }

  /// The one paused state that must not say "Off": it resolves on its own, and
  /// telling the user sync is off invites them to fix something that is not
  /// broken.
  func testTemporarilyUnavailableDoesNotClaimSyncIsOff() {
    let text = StorageModeDisplay.text(for: .cloudKitPaused(.temporarilyUnavailable))

    XCTAssertEqual(text, "Waiting for iCloud")
    XCTAssertFalse(text.contains("Off"))
  }

  /// The actionable one. A user signed out of iCloud can fix this in a minute
  /// if they are told where to go, and never if they are not.
  func testTheSignedOutCaptionNamesTheSettingsApp() {
    let caption = StorageModeDisplay.caption(for: .cloudKitPaused(.noAccount))

    XCTAssertNotNil(caption)
    XCTAssertTrue(caption?.contains("Settings app") == true)
    XCTAssertTrue(caption?.contains("Sign in to iCloud") == true)
  }

  func testAnUndeterminedStatusCarriesItsDetailThrough() {
    let caption = StorageModeDisplay.caption(for: .cloudKitPaused(.couldNotDetermine("CKError 4")))

    XCTAssertTrue(
      caption?.contains("CKError 4") == true,
      "developer-shaped text, deliberately: a user who can read it out gives a usable report")
  }

  /// The invariant across every non-syncing state, checked in one place so a
  /// later case cannot quietly skip it. The report this row exists to prevent
  /// is "the app lost my data" — reassurance comes before explanation.
  func testEveryNonSyncingCaptionOpensBySayingTheDataIsSafe() {
    let modes: [StorageMode] = [
      .localOnly(reason: "boom"),
      .cloudKitPaused(.noAccount),
      .cloudKitPaused(.restricted),
      .cloudKitPaused(.temporarilyUnavailable),
      .cloudKitPaused(.couldNotDetermine("boom")),
    ]

    for mode in modes {
      let caption = StorageModeDisplay.caption(for: mode)
      XCTAssertTrue(
        caption?.hasPrefix("Your data is safe on this device") == true,
        "\(mode) opens with: \(caption ?? "nil")")
    }
  }

  /// `isSyncing` is what the row's styling keys off, so a paused state
  /// reporting `true` would render as "On" no matter what the text says.
  /// `reason` stays construction-only — the paused states explain themselves
  /// through `SyncPauseReason`, not through an error string.
  func testAPausedModeIsNotSyncingAndCarriesNoConstructionReason() {
    for reason: SyncPauseReason in [
      .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine("x"),
    ] {
      XCTAssertFalse(StorageMode.cloudKitPaused(reason).isSyncing)
      XCTAssertNil(StorageMode.cloudKitPaused(reason).reason)
    }
  }

  // MARK: - ST: Not matched disclosure and the mail attention row

  func testNotMatchedTitleCarriesTheCount() {
    XCTAssertEqual(SettingsLogic.notMatchedTitle(count: 2), "Not matched (2)")
    XCTAssertEqual(SettingsLogic.notMatchedTitle(count: 1), "Not matched (1)")
  }

  func testAttentionTitleForEachNotConnectedState() {
    XCTAssertEqual(SettingsLogic.attentionTitle(for: .disconnected), "Mail disconnected")
    XCTAssertEqual(SettingsLogic.attentionTitle(for: .connecting), "Connecting…")
    XCTAssertEqual(SettingsLogic.attentionTitle(for: .failed(.connectionFailed)), "Couldn’t reach your mail")
    XCTAssertEqual(SettingsLogic.attentionTitle(for: .failed(.authenticationFailed)), "Couldn’t reach your mail")
  }

  func testConnectedMailHasNoAttentionTitle() {
    XCTAssertNil(SettingsLogic.attentionTitle(for: .connected(address: "a@example.com", lastSync: nil)))
  }
}

// MARK: - ST / A-07: the About privacy statement

final class AboutPrivacyTextTests: XCTestCase {
  /// DEC-07 (nomi-ios-decisions.md), verbatim. A change to `AboutScreen.privacyText`
  /// must come with a re-read of DEC-07 and a fresh App Store privacy check.
  private let dec07 =
    "Nomi reads transaction emails from the mail account you connect and keeps your transactions on this device. If you use iCloud, they also sync to your private iCloud storage so your other devices can show them. Your mail password is kept in this device's Keychain and is sent only to your mail provider to sign in. It does not sync, so you may need to enter it again on another device. Nomi does not send your data to its developer."

  func testPrivacyTextIsTheDEC07SentenceVerbatim() {
    XCTAssertEqual(AboutScreen.privacyText, dec07)
  }

  /// The shipped sentence claimed the mail credential "never leave[s] your
  /// device" except through iCloud. Both halves are false against the code
  /// (DEC-07, Problem item 2), so neither may come back.
  func testPrivacyTextDoesNotRestoreTheShippedClaim() {
    XCTAssertFalse(AboutScreen.privacyText.contains("never leave"))
    XCTAssertFalse(AboutScreen.privacyText.contains("mail credentials"))
  }

  /// Amendment 4 (R2): "stays" and "each device" overstate what the Keychain item
  /// does, because a backup restore can carry it. Neither the About sentence nor
  /// the Connect mail caption may use them. Checked over both strings.
  func testNeitherPrivacyStringOverstatesTheCredential() {
    for text in [AboutScreen.privacyText, ConnectMailCopy.credentialCaption] {
      for banned in ["stays", "each device", "never leave"] {
        XCTAssertFalse(
          text.lowercased().contains(banned),
          "'\(banned)' overstates the Keychain item: \(text)")
      }
    }
  }
}
