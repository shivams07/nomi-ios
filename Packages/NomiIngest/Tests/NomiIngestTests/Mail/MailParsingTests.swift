import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The pieces the fixtures exercise indirectly, pinned directly so a regression
/// says which part broke.
final class MailParsingTests: XCTestCase {

  // MARK: - Money is Int paise, never a Double (R9)

  func testPaiseConversionIsIntegerArithmetic() {
    XCTAssertEqual(MailAmount.paise(fromDigits: "4,500.75"), 450_075)
    XCTAssertEqual(MailAmount.paise(fromDigits: "4,500.7"), 450_070)
    XCTAssertEqual(MailAmount.paise(fromDigits: "4,500"), 450_000)
    XCTAssertEqual(MailAmount.paise(fromDigits: "0.01"), 1)
    XCTAssertEqual(MailAmount.paise(fromDigits: "1,00,000.00"), 10_000_000)
  }

  func testMalformedAmountsReturnNilRatherThanTrapping() {
    XCTAssertNil(MailAmount.paise(fromDigits: "4,500."))
    XCTAssertNil(MailAmount.paise(fromDigits: "4.5000"))
    XCTAssertNil(MailAmount.paise(fromDigits: "abc"))
    XCTAssertNil(MailAmount.paise(fromDigits: ""))
    // A forty-digit run in a malformed mail must flag a row, not crash a
    // background sync the user cannot see.
    XCTAssertNil(MailAmount.paise(fromDigits: String(repeating: "9", count: 40)))
  }

  func testAllFourCurrencyFormsAreRecognised() {
    XCTAssertEqual(MailAmount.firstAmount(in: "₹1,234.50 debited"), 123_450)
    XCTAssertEqual(MailAmount.firstAmount(in: "INR 1,234.50 debited"), 123_450)
    XCTAssertEqual(MailAmount.firstAmount(in: "Rs. 1,234.50 debited"), 123_450)
    XCTAssertEqual(MailAmount.firstAmount(in: "Rs 1,234.50 debited"), 123_450)
    XCTAssertEqual(MailAmount.firstAmount(in: "1,234.50 INR debited"), 123_450)
  }

  func testLargestAmountIsLayerTwosRuleAndFirstAmountIsNot() {
    let text = "Rs 250.00 debited. Available balance Rs 18,400.00."
    XCTAssertEqual(MailAmount.firstAmount(in: text), 25_000)
    XCTAssertEqual(MailAmount.largestAmount(in: text), 1_840_000)
  }

  // MARK: - R6: the split amount

  func testASplitDecimalIsRejoinedInAllThreeShapes() {
    XCTAssertEqual(MailHTML.rejoinSplitDecimals("Rs 4,500 .00 debited"), "Rs 4,500.00 debited")
    XCTAssertEqual(MailHTML.rejoinSplitDecimals("Rs 4,500. 00 debited"), "Rs 4,500.00 debited")
    XCTAssertEqual(MailHTML.rejoinSplitDecimals("INR 2,349 . 75 debited"), "INR 2,349.75 debited")
  }

  /// The rule that would have been easier to write is the one that corrupts a
  /// statement table. Two adjacent amounts must survive untouched.
  func testTwoAdjacentAmountsAreNotGluedTogether() {
    let joined = MailHTML.rejoinSplitDecimals("1,200 3,400")
    XCTAssertEqual(joined, "1,200 3,400")
    XCTAssertEqual(MailAmount.allAmounts(in: "Rs 1,200 Rs 3,400"), [120_000, 340_000])
  }

  func testHTMLTablesBecomeSpacedTextAndInlineTagsDoNot() {
    let cells = MailHTML.plainText(fromHTML: "<table><tr><td>Rs.</td><td>4,500.00</td></tr></table>")
    XCTAssertTrue(cells.contains("Rs. 4,500.00"), cells)

    // A <span> wrapping part of an amount must NOT introduce a space.
    let spanned = MailHTML.plainText(fromHTML: "<table><tr><td>₹<span>4,500</span>.<span>00</span></td></tr></table>")
    XCTAssertTrue(spanned.contains("₹4,500.00"), spanned)
  }

  func testNonBreakingSpacesBecomeOrdinaryOnes() {
    let text = MailHTML.plainText(fromHTML: "<table><tr><td>Rs.&nbsp;750.25&nbsp;has been debited</td></tr></table>")
    XCTAssertEqual(MailAmount.firstAmount(in: text), 75_025)
  }

  // MARK: - Dates

  /// Fixed at IST, not `TimeZone.current`. A device-dependent instant here would
  /// give two of the user's devices two different `dedupeKey`s for one email
  /// (§1.5).
  func testBodyDatesParseInISTRegardlessOfTheDeviceZone() {
    let expected = MailFixtures.date(2026, 8, 13)
    for text in ["on 13-08-2026", "on 13/08/2026", "on 13-Aug-2026", "on 2026-08-13"] {
      XCTAssertEqual(MailDate.firstDate(in: text), expected, text)
    }
  }

  func testHeaderDatesAreAbsoluteInstants() {
    let withZoneName = MailDate.parseHeaderDate("Thu, 13 Aug 2026 19:41:02 +0530 (IST)")
    let withoutZoneName = MailDate.parseHeaderDate("Thu, 13 Aug 2026 19:41:02 +0530")
    XCTAssertNotNil(withZoneName)
    XCTAssertEqual(withZoneName, withoutZoneName)
  }

  func testUnparseableDateTextYieldsNil() {
    XCTAssertNil(MailDate.firstDate(in: "no date here"))
    XCTAssertNil(MailDate.parseHeaderDate("not a date"))
  }

  // MARK: - RFC 5322

  func testHeadersAreUnfoldedAndTheSenderDomainIsExtracted() {
    let raw = """
      From: HDFC Bank InstaAlerts
       <alerts@hdfcbank.net>
      Subject: Transaction
       alert
      Date: Thu, 13 Aug 2026 19:41:02 +0530
      Content-Type: text/plain; charset=UTF-8

      Rs 100.00 debited
      """
    let message = RFC822Message.parse(raw, uid: 7, uidValidity: 2)

    XCTAssertEqual(message.subject, "Transaction alert")
    XCTAssertEqual(message.senderAddress, "alerts@hdfcbank.net")
    XCTAssertEqual(message.senderDomain, "hdfcbank.net")
    XCTAssertEqual(message.textBody?.trimmingCharacters(in: .whitespacesAndNewlines),
                   "Rs 100.00 debited")
  }

  func testQuotedPrintableAndEncodedWordSubjectsDecode() {
    let raw = """
      From: <alerts@hdfcbank.net>
      Subject: =?UTF-8?Q?=E2=82=B94,500_debited?=
      Date: Thu, 13 Aug 2026 19:41:02 +0530
      Content-Type: text/plain; charset=UTF-8
      Content-Transfer-Encoding: quoted-printable

      Amount =E2=82=B94,500.00 has been debited
      """
    let message = RFC822Message.parse(raw, uid: 8, uidValidity: 2)

    XCTAssertEqual(message.subject, "₹4,500 debited")
    XCTAssertEqual(MailAmount.firstAmount(in: message.extractableText()), 450_000)
  }

  func testMultipartAlternativePrefersTheHTMLPart() {
    let raw = """
      From: <alerts@hdfcbank.net>
      Subject: Transaction alert
      Date: Thu, 13 Aug 2026 19:41:02 +0530
      MIME-Version: 1.0
      Content-Type: multipart/alternative; boundary="B"

      --B
      Content-Type: text/plain; charset=UTF-8

      plain fallback
      --B
      Content-Type: text/html; charset=UTF-8

      <html><body><p>Rs 4,500.00 has been debited</p></body></html>
      --B--
      """
    let message = RFC822Message.parse(raw, uid: 9, uidValidity: 2)

    XCTAssertNotNil(message.htmlBody)
    XCTAssertNotNil(message.textBody)
    XCTAssertTrue(message.extractableText().contains("4,500.00"))
    XCTAssertFalse(message.extractableText().contains("plain fallback"))
  }

  func testAPlainTextOnlyMessageStillExtracts() {
    let raw = """
      From: <alerts@axisbank.com>
      Subject: Debit transaction alert
      Date: Wed, 19 Aug 2026 21:14:33 +0530
      Content-Type: text/plain; charset=UTF-8

      INR 5,000.00 has been debited from your A/c no. XX9930 on 19-08-2026.
      """
    let message = RFC822Message.parse(raw, uid: 11, uidValidity: 2)
    let draft = MailTransactionExtractor().outcome(for: message).draft

    XCTAssertEqual(draft?.amountMinor, 500_000)
    XCTAssertEqual(draft?.direction, .debit)
  }

  // MARK: - The pack

  func testTheBundledPackShipsFiveProvisionalEntriesAndSaysItIsProvisional() {
    let pack = SenderPack.bundled
    XCTAssertEqual(pack.entries.count, 5)
    XCTAssertEqual(
      Set(pack.entries.map(\.senderDomain)),
      ["sbi.co.in", "hdfcbank.net", "icicibank.com", "axisbank.com", "kotak.com"])
    // The header comment is the contract, not decoration (§2.5.1).
    XCTAssertTrue(pack.readme.contains("PROVISIONAL"))
    XCTAssertTrue(pack.readme.lowercased().contains("not a claim"))
  }

  func testPackEntriesMatchOnSubdomainsBecauseBanksAddAlertHostsWithoutNotice() {
    let entry = SenderPack.bundled.entry(
      forDomain: "alerts.hdfcbank.net", subject: "Transaction alert")
    XCTAssertEqual(entry?.bankLabel, "HDFC Bank")
  }

  func testASubjectThatDoesNotMatchTheEntryPatternDoesNotHitLayerOne() {
    XCTAssertNil(
      SenderPack.bundled.entry(forDomain: "hdfcbank.net", subject: "Your monthly newsletter"))
  }
}
