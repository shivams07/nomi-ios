import Foundation
import XCTest

@testable import NomiIngest

/// U18 / M9. The app has no exchange-rate source and does not guess one, so a
/// foreign amount is never converted — it is carried with its code and excluded
/// from every total. These tests are about reading the code and the number
/// correctly, and about not disturbing the rupee path on the way.
final class MailForeignAmountTests: XCTestCase {

  // MARK: - Reading a foreign amount

  func testAnISOCodeBeforeTheNumber() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "Card ending 4471 charged USD 12.99 at ACME"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299))
  }

  func testACurrencySymbolBeforeTheNumber() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "Card ending 4471 charged $12.99 at ACME"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299))
  }

  func testTheCodeAfterTheNumber() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "An amount of 12.99 USD was debited"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299))
  }

  func testTheOtherSymbolsAndCodes() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged €45.50"),
      MailAmount.ForeignAmount(currencyCode: "EUR", minor: 4550))
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged £8.00"),
      MailAmount.ForeignAmount(currencyCode: "GBP", minor: 800))
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged AED 120.00"),
      MailAmount.ForeignAmount(currencyCode: "AED", minor: 12000))
  }

  /// `US$` is one token, not `$` with a stray U-S in front. Ordering the symbol
  /// alternation longest-first is the only reason this does not read as 0.
  func testUSDollarWrittenWithItsPrefix() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged US$12.99"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299))
  }

  func testGroupSeparatorsAreHandled() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged USD 1,234.50"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 123450))
  }

  // MARK: - Currencies with no minor unit

  /// ¥1000 is 1000 minor units, not 100000. Scaling every currency by 100 would
  /// put a hundred-fold error on a row the user is asked to confirm.
  func testAZeroDecimalCurrencyIsNotScaledByAHundred() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "charged JPY 1000"),
      MailAmount.ForeignAmount(currencyCode: "JPY", minor: 1000))
  }

  /// A yen amount with decimals is malformed. Rounding it would invent a number.
  func testAZeroDecimalCurrencyWithAFractionIsRefused() {
    XCTAssertNil(MailAmount.foreignAmount(in: "charged JPY 1000.50"))
  }

  // MARK: - What it must not read

  /// Rupees are not foreign. Were they matched here the extractor's ordering
  /// would still save it, but the two paths would disagree about the same mail.
  func testRupeeFormsAreNotForeign() {
    for text in ["₹1,089.00 debited", "INR 412.00 credited", "Rs.500 debited"] {
      XCTAssertNil(MailAmount.foreignAmount(in: text), "matched in: \(text)")
    }
  }

  /// An unsupported code is left alone rather than scaled by a guess. KWD has
  /// three minor digits; reading it as two would be wrong by a factor of ten.
  func testAnUnsupportedCurrencyIsNotRead() {
    XCTAssertNil(MailAmount.foreignAmount(in: "charged KWD 12.500"))
  }

  /// The code has to be a word. Otherwise "PLUSD" or a base64 run reads as USD.
  func testACodeInsideAWordIsNotAMatch() {
    XCTAssertNil(MailAmount.foreignAmount(in: "reference PLUSD12345"))
  }

  func testTextWithNoAmountAtAll() {
    XCTAssertNil(MailAmount.foreignAmount(in: "Your statement is ready"))
  }

  // MARK: - The rupee path is undisturbed

  /// The done-when case. A card statement billed in rupees that quotes the
  /// original foreign amount is an INR transaction: `firstAmount` must still
  /// answer with the rupee figure.
  func testAMailCarryingBothStillReadsAsRupeesFirst() {
    let text = "Your card was charged ₹1,089.00 (USD 12.99) at ACME on 02-09-2026"

    XCTAssertEqual(MailAmount.firstAmount(in: text), 108_900)
    XCTAssertEqual(
      MailAmount.foreignAmount(in: text),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299),
      "the foreign amount is still readable; it is the ordering that decides")
  }

  /// The first foreign amount by position, not by size — same rule the rupee
  /// path uses, so the two cannot disagree about which number came first.
  func testTheFirstForeignAmountByPositionWins() {
    XCTAssertEqual(
      MailAmount.foreignAmount(in: "USD 12.99 then GBP 400.00"),
      MailAmount.ForeignAmount(currencyCode: "USD", minor: 1299))
  }
}
