import Foundation
import XCTest

@testable import NomiUI

/// The per-provider guide on Connect mail (S12b). Each provider the app connects
/// to has three steps and an https app-password page; generic IMAP has neither.
/// The steps name only what the official help pages say (Corrections, S12b).
final class MailProviderGuideTests: XCTestCase {
  func testEveryProviderExceptGenericHasThreeStepsAndAnHTTPSPage() {
    for provider in MailProvider.allCases where provider != .generic {
      XCTAssertEqual(provider.steps.count, 3, "\(provider)")
      XCTAssertEqual(provider.appPasswordURL?.scheme, "https", "\(provider)")
      XCTAssertNotNil(provider.appPasswordLinkTitle, "\(provider)")
    }
  }

  func testGenericIMAPHasNoStepsAndNoPage() {
    XCTAssertEqual(MailProvider.generic.steps, [])
    XCTAssertNil(MailProvider.generic.appPasswordURL)
    XCTAssertNil(MailProvider.generic.appPasswordLinkTitle)
  }

  /// The hosts and port the connection uses. A guide change must not move them.
  func testHostsAndPortAreUnchanged() {
    XCTAssertEqual(MailProvider.gmail.fixedHost, "imap.gmail.com")
    XCTAssertEqual(MailProvider.icloud.fixedHost, "imap.mail.me.com")
    XCTAssertEqual(MailProvider.zoho.fixedHost, "imap.zoho.in")
    XCTAssertNil(MailProvider.generic.fixedHost)
    XCTAssertEqual(MailProvider.gmail.port, 993)
  }

  /// The app has no Yahoo provider (OnboardingLogic.swift). No guide text names it.
  func testNoGuideTextNamesAProviderTheAppDoesNotSupport() {
    let text = MailProvider.allCases.flatMap { $0.steps + [$0.appPasswordLinkTitle ?? ""] }
    for line in text {
      XCTAssertFalse(line.localizedCaseInsensitiveContains("yahoo"), line)
    }
  }

  /// The footnote is pinned whole: the Keychain caption (unchanged) and the scope
  /// sentence (Lim, PR #224: "keeps only transaction alerts" was untrue, because a
  /// bank statement notice passes MailPreFilter and lands in Review).
  func testFootnotePinsTheKeychainCaptionAndTheScopeSentence() {
    XCTAssertEqual(
      ConnectMailFootnote.text,
      "Your mail password is kept in this device’s Keychain. It does not sync, so you may need to enter it again on another device. Your transactions sync only if you use iCloud. Nomi looks for transactions in emails from bank and payment senders. Anything it can't read clearly goes to Review for you to check.")
  }

  func testFootnoteClaimsNoMoreThanTheCodeDoes() {
    let lowered = ConnectMailFootnote.text.lowercased()
    for banned in ["device-only", "thisdeviceonly", "stays", "each device", "never leave", "only transaction", "keeps only", "bank alert"] {
      XCTAssertFalse(lowered.contains(banned), "overstates: \(banned)")
    }
  }

  /// Pins the Gmail wording exactly. The "16-character" line is what the user
  /// matches against Google's screen (a "12-character" mutant survived review).
  func testGmailStepsArePinnedWordForWord() {
    XCTAssertEqual(
      MailProvider.gmail.steps,
      [
        "Turn on 2-Step Verification in your Google account",
        "Create an app password for Nomi",
        "Paste the 16-character password below",
      ])
  }

  /// Each provider's app-password link goes to its own account page. Pinned by
  /// host, so an appleid.apple.com mutant fails (it survived review).
  func testEachProviderLinkGoesToItsAccountHost() {
    XCTAssertEqual(MailProvider.gmail.appPasswordURL?.host, "myaccount.google.com")
    XCTAssertEqual(MailProvider.gmail.appPasswordURL?.path, "/apppasswords")
    XCTAssertEqual(MailProvider.icloud.appPasswordURL?.host, "account.apple.com")
    XCTAssertEqual(MailProvider.zoho.appPasswordURL?.host, "accounts.zoho.com")
  }
}
