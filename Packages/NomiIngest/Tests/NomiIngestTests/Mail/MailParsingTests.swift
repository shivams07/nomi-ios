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

  /// Was `testLargestAmountIsLayerTwosRuleAndFirstAmountIsNot`. Largest-wins is
  /// gone: on this sentence pair it returned 18,400.00, the balance.
  func testTheAmountRuleFollowsTheVerbAndNotTheLargestNumber() {
    let text = "Rs 250.00 debited. Available balance Rs 18,400.00."
    XCTAssertEqual(MailAmount.firstAmount(in: text), 25_000)
    XCTAssertEqual(
      MailAmount.transactionAmount(in: text, verbRange: text.range(of: "debited")), 25_000)
  }

  /// The verb rule earning its keep: here the balance comes FIRST, so neither
  /// largest-wins nor first-wins gets it right and only the clause does.
  func testTheVerbClauseWinsEvenWhenTheBalanceIsFirstInTheText() {
    let text = "Available balance Rs 18,400.00. Rs 250.00 debited."
    XCTAssertEqual(
      MailAmount.transactionAmount(in: text, verbRange: text.range(of: "debited")), 25_000)
  }

  /// No verb located in the body — the direction came from the subject. Falls
  /// back to the first amount, not the largest.
  func testWithNoVerbRangeTheFallbackIsTheFirstAmountNotTheLargest() {
    let text = "Rs 250.00. Available balance Rs 18,400.00."
    XCTAssertEqual(MailAmount.transactionAmount(in: text, verbRange: nil), 25_000)
  }

  /// `Rs.` is how most Indian alert mail writes the symbol, and its dot is not
  /// a clause boundary. While it was treated as one, the amount sat in a
  /// different clause from its own verb and the rule silently fell through to
  /// the first-amount fallback — which is right often enough to look fine and
  /// wrong exactly when the balance is quoted first, as here.
  func testTheAbbreviationDotInRsDoesNotCutTheClause() {
    let text = "Available Balance Rs.48,900.00\nRs.3,275.50 has been debited at IRCTC"
    XCTAssertEqual(
      MailAmount.transactionAmount(in: text, verbRange: text.range(of: "debited")), 327_550)
  }

  // MARK: - Block boundaries survive the HTML

  /// FAILS today. `text()` puts a single space between two `<td>`s, so nothing
  /// downstream can tell "end of cell" from "next word". A newline is the
  /// terminator `clauseAroundFirstAmount` and the amount rule both need.
  func testPlainTextKeepsABoundaryBetweenAdjacentCells() {
    let html = "<table><tr><td>Rs.100.00 debited</td><td>Available Balance Rs.900.00</td></tr></table>"
    let text = MailHTML.plainText(fromHTML: html)

    XCTAssertTrue(text.contains("\n"), "no block boundary survived: " + text)
    XCTAssertEqual(
      text.split(separator: "\n").first?.trimmingCharacters(in: .whitespaces),
      "Rs.100.00 debited")
  }

  /// The other half: collapsing whitespace must not undo it. Spaces and tabs
  /// collapse; newlines do not.
  func testNormalizeWhitespaceCollapsesSpacesButKeepsNewlines() {
    XCTAssertEqual(MailHTML.normalizeWhitespace("a   \t  b"), "a b")
    XCTAssertEqual(MailHTML.normalizeWhitespace("a  \n   b"), "a\nb")
    XCTAssertEqual(MailHTML.normalizeWhitespace("a \n \n\n b"), "a\nb")
  }

  /// `rejoinSplitDecimals` has to keep working once the cells are separated by
  /// a newline instead of a space — the split-decimal shape is *why* the cells
  /// were adjacent in the first place.
  func testASplitDecimalStillRejoinsAcrossACellBoundary() {
    XCTAssertEqual(
      MailHTML.normalizeWhitespace("Rs 4,500\n.00 debited"), "Rs 4,500.00 debited")
  }

  // MARK: - RFC 5322 4.3: the obsolete zone names

  /// FAILS today. Only numeric offsets parse, so a legal `Date:` header ending
  /// in `GMT` returns nil and `RFC822Message` files the message under 1970.
  func testAnObsoleteZoneNameParsesRatherThanFallingBackToTheEpoch() {
    let parsed = MailDate.parseHeaderDate("Mon, 17 Aug 2026 09:15:00 GMT")

    XCTAssertNotNil(parsed, "GMT is RFC 5322 4.3 legal and must parse")
    XCTAssertEqual(parsed, Date(timeIntervalSince1970: 1_786_958_100))
  }

  func testTheNumericOffsetFormStillParses() {
    XCTAssertEqual(
      MailDate.parseHeaderDate("Mon, 17 Aug 2026 14:45:00 +0530"),
      Date(timeIntervalSince1970: 1_786_958_100))
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

  /// Was `testHTMLTablesBecomeSpacedTextAndInlineTagsDoNot`, and it asserted the
  /// defect: cells joined by a SPACE. The boundary is a newline now, including
  /// the one between a currency symbol and its digits — `MailAmount`'s pattern
  /// allows whitespace there, so the split amount is still read as one amount
  /// without the two cells being glued into one clause.
  func testHTMLTablesBecomeNewlineSeparatedAndInlineTagsDoNot() {
    let cells = MailHTML.plainText(fromHTML: "<table><tr><td>Rs.</td><td>4,500.00</td></tr></table>")
    XCTAssertEqual(cells, "Rs.\n4,500.00")
    XCTAssertEqual(MailAmount.firstAmount(in: cells), 450_000)

    // A <span> wrapping part of an amount must NOT introduce a break of any kind.
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

  /// The pack is a real bundled resource, not a Swift literal (§2.10), which
  /// means it can fail in a way a literal could not: if the `resources:` line on
  /// the NomiIngest target is ever dropped, `Bundle.module` stops carrying the
  /// file and `SenderPack.bundled` silently degrades to empty. Layer 1 would
  /// then match nothing, every mail would fall to Layer 2, and every row would
  /// arrive flagged — a plausible-looking outcome with no error anywhere. This
  /// asserts the file is actually in the bundle.
  func testTheBundledPackIsLoadedFromAnActualResourceFile() throws {
    let url = try XCTUnwrap(
      SenderPack.resourceBundle.url(forResource: "senders", withExtension: "json"),
      "senders.json is not in the bundle — check `resources:` on the NomiIngest target")
    XCTAssertFalse(try Data(contentsOf: url).isEmpty)
    XCTAssertNotNil(SenderPack.load())
    XCTAssertFalse(SenderPack.bundled.entries.isEmpty)
  }

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
