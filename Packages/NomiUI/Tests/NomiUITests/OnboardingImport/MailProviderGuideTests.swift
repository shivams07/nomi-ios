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

  func testFootnoteKeepsTheKeychainClaimAndStatesTheMailScope() {
    let footnote = ConnectMailFootnote.text
    XCTAssertTrue(footnote.hasPrefix(ConnectMailCopy.credentialCaption))
    XCTAssertTrue(
      footnote.contains(
        "Nomi reads emails from bank and payment senders and keeps only transaction alerts."))
    for banned in ["device-only", "thisdeviceonly", "stays", "each device", "never leave", "only bank alert"] {
      XCTAssertFalse(footnote.lowercased().contains(banned), "overstates: \(banned)")
    }
  }
}
