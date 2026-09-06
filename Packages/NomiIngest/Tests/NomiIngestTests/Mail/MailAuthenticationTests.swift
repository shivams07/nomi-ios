import Foundation
import XCTest

@testable import NomiIngest

/// B9. The header shapes are real ones — Gmail, Outlook and a plain Dovecot box
/// all write this differently, and the parser has to survive all three without
/// reading a result off the wrong word.
final class MailAuthenticationTests: XCTestCase {

  // MARK: - The four cases the unit is specified against

  func testAGmailShapedPassLineIsAPass() {
    let raw = """
      mx.google.com;
      dkim=pass header.i=@hdfcbank.net header.s=selector1 header.b=Xg7Kd2Qa;
      spf=pass (google.com: domain of alerts@hdfcbank.net designates 203.0.113.5 \
      as permitted sender) smtp.mailfrom=alerts@hdfcbank.net;
      dmarc=pass (p=REJECT sp=REJECT dis=NONE) header.from=hdfcbank.net
      """

    XCTAssertEqual(MailAuthentication.verdict(raw), .pass)
  }

  /// DMARC is the aligned check, so it decides on its own. A message that
  /// carries a technically valid DKIM signature over a `From:` it is not aligned
  /// with is the textbook forgery, and it must not read as a pass.
  func testADmarcFailIsAFailEvenWithDkimPassing() {
    let raw = "mx.google.com; dkim=pass header.i=@mailer.example.com; "
      + "spf=pass smtp.mailfrom=bounce@mailer.example.com; "
      + "dmarc=fail (p=NONE sp=NONE dis=NONE) header.from=hdfcbank.net"

    XCTAssertEqual(MailAuthentication.verdict(raw), .fail)
  }

  /// No DMARC result at all, which is what a plain IMAP host that only runs
  /// DKIM and SPF produces. A failed signature counts here because the envelope
  /// did not vouch for the sender either.
  func testDkimFailWithASoftfailSPFAndNoDmarcIsAFail() {
    let raw = "mx.example.net; dkim=fail reason=\"signature verification failed\" "
      + "header.i=@hdfcbank.net; spf=softfail (mx.example.net: transitioning domain) "
      + "smtp.mailfrom=alerts@hdfcbank.net"

    XCTAssertEqual(MailAuthentication.verdict(raw), .fail)
  }

  func testAnAbsentHeaderIsUnknownRatherThanEitherAnswer() {
    XCTAssertEqual(MailAuthentication.verdict(nil), .unknown)
    XCTAssertEqual(MailAuthentication.verdict(""), .unknown)
    XCTAssertEqual(MailAuthentication.verdict("   "), .unknown)
  }

  // MARK: - The edges the four cases do not cover

  /// The whole reason `unknown` exists as a third case. A forwarded message
  /// fails SPF by construction and a generic IMAP host reports `none`; treating
  /// either as a fail would flag half the mail in a forwarded mailbox.
  func testForwarderShapedResultsAreUnknownNotFail() {
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; spf=none"), .unknown)
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; dkim=none; spf=neutral"), .unknown)
    XCTAssertEqual(
      MailAuthentication.verdict("mx.example.net; dkim=temperror; spf=permerror"), .unknown)
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net"), .unknown)
  }

  /// An SPF pass alone is a pass: the envelope sender is vouched for, and a bank
  /// that has not deployed DKIM is not a forgery.
  func testASpfPassAloneIsEnough() {
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; spf=pass"), .pass)
  }

  /// A DKIM failure the envelope covers is not a fail. Mailing lists rewrite
  /// bodies and break signatures constantly while still passing SPF.
  func testDkimFailWithSpfPassingIsNotAFail() {
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; dkim=fail; spf=pass"), .pass)
  }

  /// Mail signed by both the bank and its ESP gets one `dkim=` per signature.
  /// One valid signature is a valid signature.
  func testOneOfTwoDkimSignaturesPassingIsAPass() {
    let raw = "mx.google.com; dkim=fail header.i=@esp.example.com; "
      + "dkim=pass header.i=@hdfcbank.net"

    XCTAssertEqual(MailAuthentication.verdict(raw), .pass)
  }

  /// The parser must read results off METHOD names and nothing else. This header
  /// contains `smtp.mailfrom=`, `header.d=` and an appliance's `x-dkim=`, and a
  /// word-boundary match would take a result from any of them — reading
  /// `dkim=fail` out of `x-dkim=fail` here would turn a pass into a fail.
  func testResultsAreNotReadOffLookalikeParameters() {
    let raw = "mx.example.net; spf=pass smtp.mailfrom=alerts@hdfcbank.net; "
      + "x-dkim=fail; dkim=pass header.d=hdfcbank.net"

    XCTAssertEqual(MailAuthentication.verdict(raw), .pass)
  }

  func testTheHeaderIsMatchedCaseInsensitively() {
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; DMARC=FAIL"), .fail)
    XCTAssertEqual(MailAuthentication.verdict("mx.example.net; DKIM=Pass"), .pass)
  }

  // MARK: - Through the parser

  /// The header reaches `MailMessage` at all, and it is the TOPMOST one.
  ///
  /// Each hop prepends its own, so the first is the receiving server's and the
  /// rest were written by machines a forger may control. `RFC822Message` keeps
  /// the first occurrence of a duplicate header, and this is the test that says
  /// that behaviour is load-bearing rather than incidental.
  func testTheTopmostAuthenticationResultsHeaderIsTheOneKept() {
    let raw = [
      "Authentication-Results: mx.google.com; dmarc=fail header.from=hdfcbank.net",
      "Authentication-Results: relay.attacker.example; dmarc=pass header.from=hdfcbank.net",
      "From: HDFC Bank <alerts@hdfcbank.net>",
      "Subject: Debit transaction alert",
      "Date: Wed, 2 Sep 2026 11:04:12 +0530",
      "",
      "Rs. 100.00 has been debited from account no. XX4471.",
    ].joined(separator: "\r\n")

    let message = RFC822Message.parse(raw, uid: 1, uidValidity: 900_100)

    XCTAssertEqual(
      message.authenticationResultsRaw,
      "mx.google.com; dmarc=fail header.from=hdfcbank.net")
    XCTAssertEqual(MailAuthentication.verdict(message.authenticationResultsRaw), .fail)
  }

  /// A folded header is one value, not three. Gmail folds this one every time,
  /// and a parser that read only the first physical line would see
  /// `mx.google.com;` and nothing else — `unknown` for every message Gmail
  /// delivers.
  func testAFoldedHeaderIsUnfoldedBeforeItIsRead() throws {
    let message = try MailFixtures.message("spoofed_hdfc_dkim_fail.eml")
    let raw = try XCTUnwrap(message.authenticationResultsRaw)

    XCTAssertTrue(raw.contains("dkim=fail"), raw)
    XCTAssertTrue(raw.contains("spf=softfail"), raw)
    XCTAssertFalse(raw.contains("dmarc="), "the fixture deliberately has no dmarc result")
    XCTAssertEqual(MailAuthentication.verdict(raw), .fail)
  }

  /// Every fixture that is not the spoofed one has no such header, so nothing
  /// this unit added can flag a message that was fine before it.
  func testNoExistingFixtureBecomesUnauthenticated() throws {
    for file in MailFixtures.packFixtures + MailFixtures.promotionalFixtures {
      let message = try MailFixtures.message(file)
      XCTAssertNotEqual(
        MailAuthentication.verdict(message.authenticationResultsRaw), .fail, file)
    }
  }
}
