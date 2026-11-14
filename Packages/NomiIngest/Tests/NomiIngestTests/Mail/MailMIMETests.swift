import Foundation
import XCTest

@testable import NomiIngest

/// MIME boundary case and parameter quoting (X5), and charset-aware decoding of
/// quoted-printable parts and RFC 2047 encoded words (Y12). Messages are built
/// inline with CRLF line endings, as they arrive from IMAP.
final class MailMIMETests: XCTestCase {

  private func message(_ lines: [String]) -> String {
    lines.joined(separator: "\r\n")
  }

  // MARK: - X5: boundary case and parameter quoting

  /// The outer boundary is upper-case and the nested one mixes case. Lowercasing
  /// the part's Content-Type before reading `boundary` made the split miss and
  /// left both bodies nil.
  func testNestedBoundaryWithUpperCaseLettersIsFound() {
    let raw = message([
      "From: <alerts@hdfcbank.net>",
      "Subject: Transaction alert",
      "Date: Thu, 13 Aug 2026 19:41:02 +0530",
      "MIME-Version: 1.0",
      "Content-Type: multipart/mixed; boundary=\"OUTER\"",
      "",
      "--OUTER",
      "Content-Type: multipart/alternative; boundary=\"InNeR_7Ab\"",
      "",
      "--InNeR_7Ab",
      "Content-Type: text/plain; charset=UTF-8",
      "",
      "Rs 500 debited",
      "--InNeR_7Ab",
      "Content-Type: text/html; charset=UTF-8",
      "",
      "<html><body><p>Rs 500 debited</p></body></html>",
      "--InNeR_7Ab--",
      "--OUTER--",
    ])

    let parsed = RFC822Message.parse(raw, uid: 1, uidValidity: 1)

    XCTAssertEqual(parsed.textBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                   "Rs 500 debited")
    XCTAssertNotNil(parsed.htmlBody)
  }

  /// A quoted boundary may contain spaces. The unquoted-only pattern read `a`
  /// and found no parts.
  func testQuotedBoundaryWithSpaceIsRead() {
    let raw = message([
      "From: <alerts@hdfcbank.net>",
      "Subject: Transaction alert",
      "Date: Thu, 13 Aug 2026 19:41:02 +0530",
      "Content-Type: multipart/alternative; boundary=\"a b c\"",
      "",
      "--a b c",
      "Content-Type: text/plain; charset=UTF-8",
      "",
      "plain part",
      "--a b c",
      "Content-Type: text/html; charset=UTF-8",
      "",
      "<p>html part</p>",
      "--a b c--",
    ])

    let parsed = RFC822Message.parse(raw, uid: 2, uidValidity: 1)

    XCTAssertEqual(parsed.textBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                   "plain part")
    XCTAssertEqual(parsed.htmlBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                   "<p>html part</p>")
  }

  // MARK: - Y12: charset-aware quoted-printable

  /// windows-1252 has no rupee sign, so this checks the é. A rupee in a Latin
  /// body cannot occur; the rupee case is `testQuotedPrintableUTF8StillWins`.
  func testQuotedPrintableWindows1252Rupee() {
    let raw = message([
      "From: <alerts@hdfcbank.net>",
      "Subject: Test",
      "Date: Thu, 13 Aug 2026 19:41:02 +0530",
      "Content-Type: text/plain; charset=windows-1252",
      "Content-Transfer-Encoding: quoted-printable",
      "",
      "Caf=E9",
    ])

    let parsed = RFC822Message.parse(raw, uid: 3, uidValidity: 1)

    XCTAssertEqual(parsed.textBody?.trimmingCharacters(in: .whitespacesAndNewlines), "Café")
  }

  /// A declared Latin-1 charset does not override bytes that are valid UTF-8:
  /// UTF-8 is tried first, by design.
  func testQuotedPrintableUTF8StillWins() {
    let raw = message([
      "From: <alerts@hdfcbank.net>",
      "Subject: Test",
      "Date: Thu, 13 Aug 2026 19:41:02 +0530",
      "Content-Type: text/plain; charset=iso-8859-1",
      "Content-Transfer-Encoding: quoted-printable",
      "",
      "=E2=82=B9500",
    ])

    let parsed = RFC822Message.parse(raw, uid: 4, uidValidity: 1)

    XCTAssertEqual(parsed.textBody?.trimmingCharacters(in: .whitespacesAndNewlines), "₹500")
  }

  // MARK: - Y12: RFC 2047 encoded words

  func testEncodedWordLatin1() {
    XCTAssertEqual(RFC822Message.decodeEncodedWords("=?ISO-8859-1?Q?Caf=E9?="), "Café")
    XCTAssertEqual(RFC822Message.decodeEncodedWords("=?ISO-8859-1?B?Q2Fm6Q==?="), "Café")
  }

  // MARK: - Unchanged single-part behaviour

  func testUnchangedPlainMessage() {
    let raw = message([
      "From: <alerts@axisbank.com>",
      "Subject: Debit transaction alert",
      "Date: Wed, 19 Aug 2026 21:14:33 +0530",
      "Content-Type: text/plain; charset=UTF-8",
      "",
      "INR 5,000.00 has been debited from your A/c no. XX9930 on 19-08-2026.",
    ])

    let parsed = RFC822Message.parse(raw, uid: 5, uidValidity: 1)

    XCTAssertEqual(
      parsed.textBody,
      "INR 5,000.00 has been debited from your A/c no. XX9930 on 19-08-2026.")
    XCTAssertNil(parsed.htmlBody)
    XCTAssertEqual(parsed.subject, "Debit transaction alert")
  }
}
