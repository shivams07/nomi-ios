import XCTest
@testable import NomiUI

final class NomiFormattersTests: XCTestCase {
  func testDayMonthAdaptiveOmitsYearWithinTheSameCalendarYear() {
    let reference = date(year: 2026, month: 9, day: 3)
    let sameYear = date(year: 2026, month: 1, day: 15)

    let text = NomiFormatters.dayMonthAdaptive(sameYear, relativeTo: reference)

    XCTAssertFalse(text.contains("2026"))
  }

  func testDayMonthAdaptiveIncludesYearAcrossCalendarYears() {
    let reference = date(year: 2026, month: 9, day: 3)
    let priorYear = date(year: 2025, month: 12, day: 20)

    let text = NomiFormatters.dayMonthAdaptive(priorYear, relativeTo: reference)

    XCTAssertTrue(text.contains("2025"))
  }

  // MARK: - U18: amountString(minor:currencyCode:)

  /// CI-verified (twice, across two different `NumberFormatter`
  /// constructions with byte-identical results): `en_IN`'s ICU data renders
  /// a non-INR currency's symbol plain — `"$"`, not a hand-guessed `"US$"` —
  /// with a locale-supplied space before the digits. Asserting the exact
  /// separator character would be re-guessing the same way the first two
  /// CI runs already got wrong; symbol, amount and absence of the wrong
  /// symbol are what this function actually promises.
  func testAmountStringUSDUsesDollarSymbolWithTwoFractionDigits() {
    let text = NomiFormatters.amountString(minor: 1299, currencyCode: "USD")
    XCTAssertTrue(text.hasPrefix("$"), "expected a leading $, got \(text)")
    XCTAssertTrue(text.contains("12.99"), "expected two fraction digits, got \(text)")
    XCTAssertFalse(text.contains("₹"), "a USD amount must not carry the rupee symbol")
  }

  func testAmountStringJPYHasNoFractionDigits() {
    let text = NomiFormatters.amountString(minor: 1000, currencyCode: "JPY")
    XCTAssertFalse(text.contains("."))
  }

  func testAmountStringINRMatchesTheUnchangedPath() {
    XCTAssertEqual(
      NomiFormatters.amountString(minor: 1299, currencyCode: "INR"),
      NomiFormatters.amountString(minor: 1299))
  }

  private func date(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return Calendar(identifier: .gregorian).date(from: components)!
  }
}
