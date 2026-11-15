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

  // MARK: - Display model (what the amount field draws)

  /// Fixture: no decimal point typed. The digits are ink and a dimmed ".00"
  /// follows, the artboard's ₹360.00.
  func testWholeAmountShowsADimmedPointZeroZeroSuffix() {
    XCTAssertEqual(
      EntryAmountDisplay.of("360", locale: Locale(identifier: "en_IN")),
      EntryAmountDisplay(integer: "360", typedDecimals: "", suffix: ".00")
    )
  }

  /// Fixture: "360.5". Only the typed decimal part is dimmed, and no suffix is
  /// added over what the user typed.
  func testTypedDecimalsAreDimmedAndNoSuffixIsAdded() {
    XCTAssertEqual(
      EntryAmountDisplay.of("360.5", locale: Locale(identifier: "en_IN")),
      EntryAmountDisplay(integer: "360", typedDecimals: ".5", suffix: "")
    )
  }

  /// Fixture: "360." (a separator typed, no digits yet). The separator is dimmed
  /// and no ".00" is added on top of it.
  func testATrailingSeparatorIsDimmedWithNoSuffix() {
    XCTAssertEqual(
      EntryAmountDisplay.of("360.", locale: Locale(identifier: "en_IN")),
      EntryAmountDisplay(integer: "360", typedDecimals: ".", suffix: "")
    )
  }

  /// Fixture: ".5" (no whole part). The decimals are dimmed and nothing is ink.
  func testALeadingSeparatorHasNoIntegerPart() {
    XCTAssertEqual(
      EntryAmountDisplay.of(".5", locale: Locale(identifier: "en_IN")),
      EntryAmountDisplay(integer: "", typedDecimals: ".5", suffix: "")
    )
  }

  /// An empty field shows nothing here, so the "0" placeholder is not followed by
  /// a ".00" that would read as a typed amount.
  func testAnEmptyFieldHasNoSuffix() {
    XCTAssertEqual(
      EntryAmountDisplay.of("", locale: Locale(identifier: "en_IN")),
      EntryAmountDisplay(integer: "", typedDecimals: "", suffix: "")
    )
  }

  /// The separator is the device's, so a German keyboard's comma is dimmed like
  /// the point in en_IN.
  func testTheSeparatorFollowsTheLocale() {
    XCTAssertEqual(
      EntryAmountDisplay.of("12,50", locale: Locale(identifier: "de_DE")),
      EntryAmountDisplay(integer: "12", typedDecimals: ",50", suffix: "")
    )
  }

  /// The decimals dim at the same opacity as NomiAmountText's rule for an amount
  /// this size (0.5 at 24 pt and above). It is pinned here so the field and the
  /// amounts elsewhere cannot drift apart.
  func testDecimalsDimAtTheAmountRuleOpacity() {
    XCTAssertEqual(EntryAmountDisplay.decimalOpacity, 0.5)
    XCTAssertEqual(EntryAmountDisplay.decimalOpacity, NomiAmountText.decimalsOpacity(for: .heroAmount))
  }
}
