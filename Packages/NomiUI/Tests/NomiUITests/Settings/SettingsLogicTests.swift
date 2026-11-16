import Foundation
import NomiCore
import XCTest
@testable import NomiUI

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

  /// The row's caption names the threshold the app really uses (`thresholdFraction`), so a
  /// changed threshold cannot leave a stale "90%" under the switch.
  func testBudgetAlertCaptionNamesTheThreshold() {
    XCTAssertEqual(SettingsLogic.budgetAlertsCaption(thresholdFraction: 0.9), "At 90% and when you go over")
    XCTAssertEqual(SettingsLogic.budgetAlertsCaption(thresholdFraction: 0.8), "At 80% and when you go over")
  }

  // MARK: - B11: the storage mode is visible to the user, not just to Xcode

  func testSyncingReadsAsOnWithNoCaption() {
    XCTAssertEqual(StorageModeDisplay.text(for: .cloudKit), "On")
    XCTAssertNil(
      StorageModeDisplay.caption(for: .cloudKit),
      "one line when there is nothing to explain")
  }

  // MARK: - S9a step 4: the local fallback is a plain sentence, and its reason is copyable

  /// The caption is a sentence a person can read. The reason is developer text and
  /// moves to "Copy details", so it must not appear in the caption.
  func testTheLocalFallbackCaptionIsAPlainSentenceWithoutTheReason() {
    let reason = "CKError: Not entitled"
    let mode = StorageMode.localOnly(reason: reason)

    XCTAssertEqual(StorageModeDisplay.text(for: mode), "Off — this device only")
    XCTAssertEqual(
      StorageModeDisplay.caption(for: mode),
      "Nomi couldn’t start iCloud sync, so everything is kept on this iPhone.")
    XCTAssertFalse(StorageModeDisplay.caption(for: mode)?.contains(reason) == true)
  }

  /// "Copy details" writes the reason, and only the local fallback has one to copy.
  func testCopyableDetailsIsTheLocalFallbackReason() {
    XCTAssertEqual(
      SettingsLogic.copyableDetails(for: StorageMode.localOnly(reason: "CKError: Not entitled")),
      "CKError: Not entitled")
    XCTAssertNil(SettingsLogic.copyableDetails(for: StorageMode.cloudKit))
    XCTAssertNil(SettingsLogic.copyableDetails(for: StorageMode.cloudKitPaused(.noAccount)))
  }

  func testTheModeAccessorsAgreeWithWhatIsDisplayed() {
    XCTAssertTrue(StorageMode.cloudKit.isSyncing)
    XCTAssertNil(StorageMode.cloudKit.reason)
    XCTAssertFalse(StorageMode.localOnly(reason: "x").isSyncing)
    XCTAssertEqual(StorageMode.localOnly(reason: "x").reason, "x")
  }

  // MARK: - R7c: an in-memory store says it is not being saved, and nothing else

  func testInMemoryRowTextSaysNotBeingSaved() {
    XCTAssertEqual(StorageModeDisplay.text(for: .inMemory(reason: "x")), "Off — not being saved")
  }

  /// The caption is the reason alone. A "safe" sentence here would tell the
  /// user the opposite of what is true.
  func testInMemoryCaptionIsTheReasonAlone() {
    let reason =
      "Nomi couldn’t open your saved data this time. Nothing has been changed or deleted. Close Nomi and open it again; anything you add before then won’t be kept."
    let caption = StorageModeDisplay.caption(for: .inMemory(reason: reason))

    XCTAssertEqual(caption, reason)
    XCTAssertFalse(caption?.contains("safe") == true)
  }

  func testInMemoryIsNotSyncingAndCarriesItsReason() {
    XCTAssertFalse(StorageMode.inMemory(reason: "x").isSyncing)
    XCTAssertEqual(StorageMode.inMemory(reason: "x").reason, "x")
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
  /// is "the app lost my data" — reassurance comes before explanation. The
  /// local fallback is the one exception: its caption is the sentence that
  /// says everything is kept on this iPhone (S9a step 4), tested above.
  func testEveryPausedCaptionOpensBySayingTheDataIsSafe() {
    let modes: [StorageMode] = [
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

  // MARK: - S9a step 2: the rows' words

  func testCategoriesCountIsPluralised() {
    XCTAssertEqual(SettingsLogic.categoriesText(count: 1), "1 category")
    XCTAssertEqual(SettingsLogic.categoriesText(count: 14), "14 categories")
  }

  /// Auto-categorise counts the rules that are on and that the user made. System
  /// rules and switched-off rules do not count as merchants remembered.
  func testMerchantsRememberedCountsEnabledNonSystemRules() {
    let rules: [(isSystem: Bool, isEnabled: Bool)] = [
      (false, true), (true, true), (false, false), (false, true),
    ]
    XCTAssertEqual(SettingsLogic.merchantsRemembered(rules), 2)
    XCTAssertEqual(SettingsLogic.merchantsRememberedText(count: 1), "1 merchant remembered")
    XCTAssertEqual(SettingsLogic.merchantsRememberedText(count: 23), "23 merchants remembered")
  }

  func testAccountsCaptionIsCountAndEstimatedTotal() {
    XCTAssertEqual(SettingsLogic.accountsText(count: 1, totalMinor: 100_000), "1 account · ₹1,000.00 estimated")
    XCTAssertEqual(SettingsLogic.accountsText(count: 3, totalMinor: 11_848_100), "3 accounts · ₹1,18,481.00 estimated")
  }

  /// The tracked total can be negative (an overdrawn account or a card owed), so the
  /// sign has to show. `TrackedBalanceText` owns that rule and this text reuses it.
  func testAccountsCaptionKeepsANegativeTotalsSign() {
    XCTAssertEqual(SettingsLogic.accountsText(count: 2, totalMinor: -5_000), "2 accounts · -\u{2060}₹50.00 estimated")
  }

  // MARK: - ST: the mail attention row

  func testMailAlertsCaptionForConnectedNamesTheAddressAndWhenItWasChecked() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    XCTAssertEqual(
      SettingsLogic.mailAlertsCaption(for: .connected(address: "you@gmail.com", lastSync: now), now: now),
      "you@gmail.com · checked just now")
    XCTAssertEqual(
      SettingsLogic.mailAlertsCaption(for: .connected(address: "you@gmail.com", lastSync: nil), now: now),
      "you@gmail.com · not checked yet")
  }

  func testMailAlertsCaptionForANotConnectedStateIsTheAttentionTitle() {
    let now = Date()
    XCTAssertEqual(SettingsLogic.mailAlertsCaption(for: .disconnected, now: now), "Mail disconnected")
    XCTAssertEqual(SettingsLogic.mailAlertsCaption(for: .connecting, now: now), "Connecting…")
    XCTAssertEqual(SettingsLogic.mailAlertsCaption(for: .failed(.connectionFailed), now: now), "Couldn’t reach your mail")
  }

  func testOnlyAConnectedMailStateReadsOn() {
    XCTAssertTrue(SettingsLogic.mailIsOn(.connected(address: "a@example.com", lastSync: nil)))
    XCTAssertFalse(SettingsLogic.mailIsOn(.disconnected))
    XCTAssertFalse(SettingsLogic.mailIsOn(.connecting))
    XCTAssertFalse(SettingsLogic.mailIsOn(.failed(.connectionFailed)))
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

// MARK: - About privacy statement

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

// MARK: - R7 notice: Settings says a store was moved aside, once

final class StoreRecoveryDisplayTests: XCTestCase {
  /// 14 Nov 2026 at noon in the device's zone, built in the same zone the
  /// formatter uses, so the day cannot shift on a machine in another zone.
  private func fixedDate() throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    return try XCTUnwrap(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12)))
  }

  func testCaptionNamesTheDayAndTheRecoveredFile() throws {
    let notice = StoreRecoveryNotice(
      movedAt: try fixedDate(), fileName: "default-20261114T093012.store")
    XCTAssertEqual(
      StoreRecoveryDisplay.caption(for: notice),
      "Nomi couldn’t open its saved data on 14 Nov 2026, so it started fresh. The old data was kept on this device as default-20261114T093012.store.")
  }

  func testCaptionDoesNotShowTheFullDateTime() throws {
    let notice = StoreRecoveryNotice(
      movedAt: try fixedDate(), fileName: "default-20261114T093012.store")
    let caption = StoreRecoveryDisplay.caption(for: notice)
    XCTAssertFalse(caption.contains("12:00"))
    XCTAssertFalse(caption.contains("PM"))
    XCTAssertFalse(caption.contains("AM"))
  }
}
