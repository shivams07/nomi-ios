import Foundation
import NomiCore
import Testing

/// R8, I-8. The `minorUnits` table is the fixture the plan asks a person to
/// recompute at review; the rows marked "plan" are the plan's own, the rest are
/// the edge cases this unit adds. "\u{202F}" is the narrow no-break space that
/// fr_FR groups with.
struct AmountRulesTests {
  private func locale(_ identifier: String) -> Locale {
    Locale(identifier: identifier)
  }

  @Test func minorUnitsTableMatchesTheRecomputedValues() {
    struct Row {
      let text: String
      let localeID: String
      let allowNegative: Bool
      let expected: Int?
    }
    let rows: [Row] = [
      // plan
      Row(text: "12.50", localeID: "en_IN", allowNegative: false, expected: 1250),
      Row(text: "12,50", localeID: "de_DE", allowNegative: false, expected: 1250),
      Row(text: "12,50", localeID: "en_IN", allowNegative: false, expected: 125_000),
      Row(text: "1,234.50", localeID: "en_IN", allowNegative: false, expected: 123_450),
      Row(text: "1.234,50", localeID: "de_DE", allowNegative: false, expected: nil),
      Row(text: "१२३.४५", localeID: "hi_IN", allowNegative: false, expected: 12_345),
      Row(text: "12.345", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "1000000000", localeID: "en_IN", allowNegative: false, expected: 100_000_000_000),
      Row(text: "1000000000.01", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "12345678901234567890", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: ".", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "-500", localeID: "en_IN", allowNegative: true, expected: -50_000),
      Row(text: "-500", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "₹500", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "12\u{202F}345,67", localeID: "fr_FR", allowNegative: false, expected: 1_234_567),
      // added here
      Row(text: "0.00", localeID: "en_IN", allowNegative: false, expected: 0),
      Row(text: "1²", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "-", localeID: "en_IN", allowNegative: true, expected: nil),
      Row(text: "5-", localeID: "en_IN", allowNegative: true, expected: nil),
      Row(text: "1.999", localeID: "en_IN", allowNegative: false, expected: nil),
      Row(text: "99999999.99", localeID: "en_IN", allowNegative: false, expected: 9_999_999_999),
      Row(text: "-1,250.50", localeID: "en_IN", allowNegative: true, expected: -125_050),
      Row(text: "abc", localeID: "en_IN", allowNegative: true, expected: nil),
      Row(text: "1.2.3", localeID: "en_IN", allowNegative: false, expected: nil),
    ]
    for row in rows {
      let actual = AmountText.minorUnits(row.text, locale: locale(row.localeID), allowNegative: row.allowNegative)
      #expect(actual == row.expected, "\(row.text) in \(row.localeID), allowNegative \(row.allowNegative)")
    }
  }

  @Test func transactionAmountBoundsAreOneThroughTenToTheElevenPaise() {
    #expect(AmountRules.isValidTransactionAmount(0) == false)
    #expect(AmountRules.isValidTransactionAmount(1))
    #expect(AmountRules.isValidTransactionAmount(100_000_000_000))
    #expect(AmountRules.isValidTransactionAmount(100_000_000_001) == false)
    #expect(AmountRules.isValidTransactionAmount(-1) == false)
  }

  @Test func openingBalanceBoundsAreSymmetricAndIncludeZero() {
    #expect(AmountRules.isValidOpeningBalance(-100_000_000_000))
    #expect(AmountRules.isValidOpeningBalance(-100_000_000_001) == false)
    #expect(AmountRules.isValidOpeningBalance(0))
  }

  @Test func filteredKeepsDigitsTheFirstSeparatorAndALeadingMinusOnlyWhenAllowed() {
    #expect(AmountText.filtered("₹500", locale: locale("en_IN"), allowNegative: false) == "500")
    #expect(AmountText.filtered("1a2b3", locale: locale("en_IN"), allowNegative: false) == "123")
    #expect(AmountText.filtered("12.5.6", locale: locale("en_IN"), allowNegative: false) == "12.56")
    #expect(AmountText.filtered("-500", locale: locale("en_IN"), allowNegative: true) == "-500")
    #expect(AmountText.filtered("-500", locale: locale("en_IN"), allowNegative: false) == "500")
    #expect(AmountText.filtered(" -5", locale: locale("en_IN"), allowNegative: true) == "5")
    #expect(AmountText.filtered("5-00", locale: locale("en_IN"), allowNegative: true) == "500")
    #expect(AmountText.filtered("१२३.४५", locale: locale("hi_IN"), allowNegative: false) == "123.45")
    #expect(AmountText.filtered("1,234.50", locale: locale("en_IN"), allowNegative: false) == "1234.50")
    #expect(AmountText.filtered("1.234,50", locale: locale("de_DE"), allowNegative: false) == "1.23450")
    #expect(AmountText.filtered("1,5", locale: locale("de_DE"), allowNegative: false) == "1,5")
    #expect(AmountText.filtered("12\u{202F}345,67", locale: locale("fr_FR"), allowNegative: false) == "12345,67")
  }

  @Test func aFilteredEntryParsesToTheSameAmountAsTheRawEntry() {
    // The field filters on each keystroke and the save path parses the result, so
    // the two must agree for every text a person can type.
    let typed = ["1,234.50", "12,50", "₹500", "1.999"]
    for text in typed {
      let filtered = AmountText.filtered(text, locale: locale("en_IN"), allowNegative: false)
      let direct = AmountText.minorUnits(text, locale: locale("en_IN"), allowNegative: false)
      let viaFilter = AmountText.minorUnits(filtered, locale: locale("en_IN"), allowNegative: false)
      if direct != nil {
        #expect(viaFilter == direct, "\(text)")
      }
    }
  }
}
