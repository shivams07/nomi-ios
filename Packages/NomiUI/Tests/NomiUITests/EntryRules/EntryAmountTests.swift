import XCTest
@testable import NomiUI

final class EntryAmountTests: XCTestCase {
  func testWholeRupeesParseToMinorUnits() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125"), 12500)
  }

  func testDecimalParsesToMinorUnits() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125.50"), 12550)
  }

  func testEmptyTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: ""), 0)
  }

  func testZeroTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "0"), 0)
  }

  func testNonNumericTextIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "abc"), 0)
  }

  func testTrailingDecimalPointParses() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "125."), 12500)
  }

  /// F7: a `Double` conversion silently turned "1.999" into ₹2.00 — this
  /// FAILS on `main`. `Decimal` rejects rather than rounds a third fraction
  /// digit, matching `MailAmount.paise`'s rule for a parsed mail amount.
  func testMoreThanTwoFractionDigitsIsRejectedNotRounded() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "1.999"), 0)
    XCTAssertEqual(EntryAmount.minorUnits(from: "12.999"), 0)
  }

  /// The classic float-rounding trap for money — 1.005 cannot be represented
  /// exactly as a binary `Double`, so a `Double`-based conversion is prone to
  /// landing on 100 instead of rejecting a third fraction digit. `Decimal`
  /// parses "1.005" exactly and this still rejects it on digit count alone.
  func testThreeFractionDigitsAtTheRoundingEdgeIsRejected() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "1.005"), 0)
  }

  func testSingleFractionDigitIsPaddedToPaise() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "1234.5"), 123450)
  }

  func testLargeAmountConvertsExactly() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "99999999.99"), 9_999_999_999)
  }

  /// R8. "1.999" is refused to zero in the entry field, as in every locale.
  func testThreeDecimalsIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "1.999"), 0)
  }

  /// R8. A German device types "," as the decimal point. It must read as one,
  /// not as grouping (which would make the amount 125000 in en_IN).
  func testLocaleCommaDecimal() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "12,50", locale: Locale(identifier: "de_DE")), 1250)
  }

  /// R8. The bounds: ₹1,00,00,00,000.00 is the largest amount, and one paisa
  /// above it is refused to zero, not wrapped.
  func testMaximumIsAcceptedAndOneOverIsZero() {
    XCTAssertEqual(EntryAmount.minorUnits(from: "1000000000", locale: Locale(identifier: "en_IN")), 100_000_000_000)
    XCTAssertEqual(EntryAmount.minorUnits(from: "1000000000.01", locale: Locale(identifier: "en_IN")), 0)
  }

  func testSanitizeStripsNonNumericCharacters() {
    XCTAssertEqual(EntryAmount.sanitizeInput("1a2b3"), "123")
  }

  func testSanitizeKeepsOnlyFirstDecimalPoint() {
    XCTAssertEqual(EntryAmount.sanitizeInput("12.5.6"), "12.56")
  }

  func testSanitizeIsIdempotentOnCleanInput() {
    XCTAssertEqual(EntryAmount.sanitizeInput("125.50"), "125.50")
  }
}
