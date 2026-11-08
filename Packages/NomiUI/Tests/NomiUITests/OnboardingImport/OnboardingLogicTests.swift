import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class OnboardingLogicTests: XCTestCase {
  func testGmailHasFixedHost() {
    XCTAssertEqual(MailProvider.gmail.fixedHost, "imap.gmail.com")
  }

  func testICloudHasFixedHost() {
    XCTAssertEqual(MailProvider.icloud.fixedHost, "imap.mail.me.com")
  }

  func testZohoHasFixedHost() {
    XCTAssertEqual(MailProvider.zoho.fixedHost, "imap.zoho.in")
  }

  func testGenericHasNoFixedHost() {
    XCTAssertNil(MailProvider.generic.fixedHost)
  }

  func testConnectFormRequiresAddressAndPassword() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "", host: "", password: "secret"))
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: ""))
  }

  func testConnectFormValidForFixedHostProviderWithoutHostEntry() {
    XCTAssertTrue(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: "secret"))
  }

  func testConnectFormRequiresHostForGenericProvider() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .generic, address: "a@b.com", host: "", password: "secret"))
    XCTAssertTrue(ConnectFormGate.isValid(provider: .generic, address: "a@b.com", host: "mail.example.com", password: "secret"))
  }

  /// B6: a pasted Google app password routinely carries a trailing newline
  /// no typed field would.
  func testNormalizedTrimsWhitespaceAndNewlines() {
    XCTAssertEqual(ConnectFormGate.normalized(" abcd efgh \n"), "abcd efgh")
  }

  func testConnectFormRejectsAnEmbeddedNewlineInThePassword() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: "ab\ncd"))
  }

  func testConnectFormRejectsAnEmbeddedNewlineInTheAddress() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "ab\ncd", host: "", password: "secret"))
  }

  func testConnectFormIsFalseForAWhitespaceOnlyPassword() {
    XCTAssertFalse(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: "   "))
  }

  func testConnectFormAcceptsATrailingNewlineOnceTrimmed() {
    XCTAssertTrue(ConnectFormGate.isValid(provider: .gmail, address: "a@b.com", host: "", password: "secret\n"))
  }

  func testMailErrorMessagesAreNamedNotGeneric() {
    XCTAssertTrue(MailErrorMessage.text(for: .authenticationFailed).lowercased().contains("password"))
    XCTAssertTrue(MailErrorMessage.text(for: .connectionFailed).lowercased().contains("connection") || MailErrorMessage.text(for: .connectionFailed).lowercased().contains("reach"))
  }

  func testUnknownMailErrorFallsBackWhenDetailIsEmpty() {
    XCTAssertFalse(MailErrorMessage.text(for: .unknown("")).isEmpty)
  }

  func testUnknownMailErrorUsesDetailWhenPresent() {
    XCTAssertEqual(MailErrorMessage.text(for: .unknown("IMAP timeout")), "IMAP timeout")
  }

  func testBackfillFractionClampsBetweenZeroAndOne() {
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 0, total: 0, created: 0)), 0)
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 50, total: 100, created: 5)), 0.5, accuracy: 0.0001)
    XCTAssertEqual(BackfillMath.fraction(BackfillProgress(scanned: 150, total: 100, created: 5)), 1)
  }

  func testBackfillCompleteOnlyWhenScannedReachesTotal() {
    XCTAssertFalse(BackfillMath.isComplete(BackfillProgress(scanned: 99, total: 100, created: 0)))
    XCTAssertTrue(BackfillMath.isComplete(BackfillProgress(scanned: 100, total: 100, created: 0)))
    XCTAssertFalse(BackfillMath.isComplete(BackfillProgress(scanned: 0, total: 0, created: 0)))
  }

  func testBackfillCompletionSummaryReportsCountersAsPlainCopy() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: [])
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertTrue(lines.contains("1200 emails scanned"))
    XCTAssertTrue(lines.contains("91 transactions found"))
    XCTAssertTrue(lines.contains("70 matched a known bank format, 21 matched generically"))
  }

  func testBackfillCompletionSummaryOmitsUnmatchedLineWhenNoneUnmatched() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: [])
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertFalse(lines.contains { $0.contains("Not matched") })
  }

  func testBackfillCompletionSummaryNamesEveryUnmatchedDomainAndCount() {
    let unmatched = [
      UnmatchedSender(domain: "chase.com", count: 3),
      UnmatchedSender(domain: "boa.com", count: 1),
    ]
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: unmatched)
    let lines = BackfillCompletionSummary.lines(for: summary)
    let unmatchedLine = lines.first { $0.contains("Not matched") }
    XCTAssertNotNil(unmatchedLine)
    for sender in unmatched {
      XCTAssertTrue(unmatchedLine!.contains("\(sender.domain) (\(sender.count))"))
    }
  }

  func testBackfillCompletionSummaryNeverEmitsAnAddress() {
    let unmatched = [
      UnmatchedSender(domain: "chase.com", count: 3),
      UnmatchedSender(domain: "boa.com", count: 1),
    ]
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: unmatched)
    let lines = BackfillCompletionSummary.lines(for: summary)
    XCTAssertFalse(lines.contains { $0.contains("@") })
  }

  /// The Done frame's count line already says scanned and found, so the detail
  /// lines must not repeat them. They keep the match breakdown and the unmatched
  /// senders, which the scan reports nowhere else on this screen.
  func testDetailLinesOmitTheCountsTheCountLineAlreadyShows() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21, unmatchedSenders: [])
    let lines = BackfillCompletionSummary.detailLines(for: summary)
    XCTAssertEqual(lines, ["70 matched a known bank format, 21 matched generically"])
  }

  func testDetailLinesKeepTheUnmatchedSenders() {
    let summary = SyncSummary(scanned: 1200, created: 91, merged: 4, flagged: 6, packMatched: 70, heuristicMatched: 21,
                              unmatchedSenders: [UnmatchedSender(domain: "boa.com", count: 1)])
    XCTAssertTrue(BackfillCompletionSummary.detailLines(for: summary).contains("Not matched: boa.com (1)"))
  }

  // MARK: - One primary per Backfill state (DEC-09, A-09 item 3)

  /// Each state shows exactly one white primary or the glass Cancel, never both.
  func testEveryBackfillStateShowsExactlyOneWhitePrimaryOrTheGlassCancel() {
    let running = BackfillControls.forPhase(.running)
    XCTAssertNil(running.primary)
    XCTAssertEqual(running.secondary, .cancel)

    for phase in [BackfillPhase.cancelled, .completed, .failed] {
      let controls = BackfillControls.forPhase(phase)
      XCTAssertNotNil(controls.primary, "\(phase) needs one white primary")
      XCTAssertNil(controls.secondary, "\(phase) must not also show Cancel")
    }
  }

  func testPausedShowsResumeAsThePrimary() {
    XCTAssertEqual(BackfillControls.forPhase(.cancelled).primary, .resume)
  }

  func testCompletedShowsDoneAsThePrimaryAndNoLeaveText() {
    let controls = BackfillControls.forPhase(.completed)
    XCTAssertEqual(controls.primary, .done)
    XCTAssertFalse(controls.showsLeave, "the white Done is the exit once the scan has finished")
  }

  func testFailedShowsRetryAsThePrimary() {
    XCTAssertEqual(BackfillControls.forPhase(.failed).primary, .retry)
  }

  /// Leaving while a scan runs must stay possible, because the scan carries on
  /// after the screen is gone. Only the finished frame has no leave text.
  func testLeaveIsAvailableUntilTheScanFinishes() {
    XCTAssertTrue(BackfillControls.forPhase(.notStarted).showsLeave)
    XCTAssertTrue(BackfillControls.forPhase(.running).showsLeave)
    XCTAssertTrue(BackfillControls.forPhase(.cancelled).showsLeave)
    XCTAssertTrue(BackfillControls.forPhase(.failed).showsLeave)
  }

  func testOnlyCancelIsSecondaryAndSecondaryIsGlassNotNavy() {
    XCTAssertEqual(BackfillControl.cancel.kind, .secondary)
    for control in [BackfillControl.resume, .done, .retry] {
      XCTAssertEqual(control.kind, .primary, "\(control) must be the white primary")
    }
  }

  func testBackfillControlTitlesAreTheShippedWords() {
    XCTAssertEqual(BackfillControl.cancel.title, "Cancel")
    XCTAssertEqual(BackfillControl.resume.title, "Resume")
    XCTAssertEqual(BackfillControl.done.title, "Done")
    XCTAssertEqual(BackfillControl.retry.title, "Retry")
  }

  // MARK: - Mail attention card (ConnectMailAttention)

  func testNoAttentionCardWhileConnectedOrConnecting() {
    let now = Date()
    XCTAssertNil(MailAttentionLogic.copy(for: .connected(address: "a@b.com", lastSync: now), hadConnection: true, lastSync: now, now: now))
    XCTAssertNil(MailAttentionLogic.copy(for: .connecting, hadConnection: true, lastSync: now, now: now))
  }

  /// A first-run user who has never connected has nothing to attend to yet.
  func testNoAttentionCardForDisconnectedWithoutAPriorConnection() {
    XCTAssertNil(MailAttentionLogic.copy(for: .disconnected, hadConnection: false, lastSync: nil, now: Date()))
  }

  func testDisconnectedAfterAConnectionSaysLastSyncedRelativeToNow() throws {
    let now = Date()
    let lastSync = now.addingTimeInterval(-2 * 86_400)
    let copy = try XCTUnwrap(MailAttentionLogic.copy(for: .disconnected, hadConnection: true, lastSync: lastSync, now: now))
    XCTAssertEqual(copy.title, "Mail disconnected")
    XCTAssertTrue(copy.message.hasPrefix("Last synced "), copy.message)
    XCTAssertTrue(copy.message.hasSuffix(" ago. Connect again to keep your numbers current."), copy.message)
  }

  func testDisconnectedAfterAConnectionWithoutASyncOmitsTheSyncSentence() throws {
    let copy = try XCTUnwrap(MailAttentionLogic.copy(for: .disconnected, hadConnection: true, lastSync: nil, now: Date()))
    XCTAssertEqual(copy.message, "Connect again to keep your numbers current.")
  }

  func testFailedStateGetsTheSettingsFailureCopy() throws {
    let copy = try XCTUnwrap(MailAttentionLogic.copy(for: .failed(.authenticationFailed), hadConnection: true, lastSync: nil, now: Date()))
    XCTAssertEqual(copy.title, "Couldn’t reach your mail")
    XCTAssertEqual(copy.message, SyncStatusRow.failureMessage(for: .authenticationFailed))
  }

  // MARK: - Seeded from persisted history (OB2, A-20 item 10)

  func testSeedFromAFreshInstallHasNoPriorConnection() {
    let seed = MailAttentionSeed(history: .never)
    XCTAssertFalse(seed.hadConnection)
    XCTAssertNil(seed.lastSync)
  }

  func testSeedCarriesEverConnectedAndLastSyncFromHistory() {
    let lastSync = Date(timeIntervalSince1970: 1_750_000_000)
    let seed = MailAttentionSeed(history: MailConnectionHistory(hasEverConnected: true, lastSync: lastSync))
    XCTAssertTrue(seed.hadConnection)
    XCTAssertEqual(seed.lastSync, lastSync)
  }

  /// A-20 item 10: `.disconnected` with history (ever connected, last sync three
  /// days ago) yields the card with "Last synced 3 days ago.".
  func testDisconnectedWithHistoryShowsTheCardWithLastSyncThreeDaysAgo() throws {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let seed = MailAttentionSeed(
      history: MailConnectionHistory(hasEverConnected: true, lastSync: now.addingTimeInterval(-3 * 86_400))
    )
    let copy = try XCTUnwrap(
      MailAttentionLogic.copy(for: .disconnected, hadConnection: seed.hadConnection, lastSync: seed.lastSync, now: now)
    )
    XCTAssertEqual(copy.title, "Mail disconnected")
    XCTAssertEqual(copy.message, "Last synced 3 days ago. Connect again to keep your numbers current.")
  }

  /// A-20 item 10: `.disconnected` with no history yields no card.
  func testDisconnectedWithNoHistoryShowsNoCard() {
    let seed = MailAttentionSeed(history: .never)
    XCTAssertNil(
      MailAttentionLogic.copy(for: .disconnected, hadConnection: seed.hadConnection, lastSync: seed.lastSync, now: Date())
    )
  }

  /// Ever connected but never synced: the card still shows, without the sync sentence.
  func testDisconnectedWithHistoryButNoSyncOmitsTheSyncSentence() throws {
    let seed = MailAttentionSeed(history: MailConnectionHistory(hasEverConnected: true, lastSync: nil))
    let copy = try XCTUnwrap(
      MailAttentionLogic.copy(for: .disconnected, hadConnection: seed.hadConnection, lastSync: seed.lastSync, now: Date())
    )
    XCTAssertEqual(copy.message, "Connect again to keep your numbers current.")
  }

  /// A-20 item 10: `.failed` is unchanged. Its copy does not depend on history.
  func testFailedCopyIsTheSameWhetherOrNotHistoryIsSeeded() {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    let fresh = MailAttentionLogic.copy(for: .failed(.connectionFailed), hadConnection: false, lastSync: nil, now: now)
    let seeded = MailAttentionLogic.copy(
      for: .failed(.connectionFailed), hadConnection: true, lastSync: now.addingTimeInterval(-86_400), now: now
    )
    XCTAssertNotNil(fresh)
    XCTAssertEqual(fresh, seeded)
  }

  // MARK: - Credential claim (DEC-07, checked against the code)

  /// Pins the caption to Amendment 4 (R2), character for character, and to the
  /// clauses the code supports. The item does not sync
  /// (`kSecAttrSynchronizable` is false, KeychainCredentialStore.swift:106), and
  /// it is not ThisDeviceOnly (line 59), so the sentence says "kept in" and
  /// "may need to", never "stays" or "each device". Transactions sync only
  /// through iCloud.
  func testCredentialCaptionClaimsOnlyWhatTheCodeSupports() {
    let caption = ConnectMailCopy.credentialCaption
    XCTAssertEqual(
      caption,
      "Your mail password is kept in this device’s Keychain. It does not sync, so you may need to enter it again on another device. Your transactions sync only if you use iCloud.")
    let lowered = caption.lowercased()
    for required in ["Keychain", "does not sync", "may need to", "Your transactions sync only if you use iCloud."] {
      XCTAssertTrue(caption.contains(required), "missing: \(required)")
    }
    for banned in ["stays", "each device", "never leave", "icloud keychain"] {
      XCTAssertFalse(lowered.contains(banned), "overstates the credential: \(banned)")
    }
  }

  /// The Backfill moment hides the status bar on every phase, so the layout does
  /// not move between frames (Amendment 4, R3). The modifier reads this constant.
  func testBackfillHidesTheStatusBarOnEveryPhase() {
    XCTAssertTrue(BackfillChrome.hidesStatusBar)
  }
}
