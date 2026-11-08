import NomiCore
import XCTest
@testable import NomiUI

/// Exercises `TransactionRow`'s pure display-logic helpers only. These tests
/// never build a `Transaction` — not because they cannot, since a container
/// constructs fine under XCTest and only swift-testing traps (see
/// `InMemoryModelContainer`'s measured note in NomiCore), but because a
/// subtitle string needs no store to assert anything about.
final class TransactionRowTests: XCTestCase {
  func testNilAccountRendersUnassigned() {
    let subtitle = TransactionRow.subtitle(categoryName: "Food", accountName: nil)
    XCTAssertTrue(subtitle.contains("Unassigned"))
  }

  func testNilCategoryRendersUncategorized() {
    let subtitle = TransactionRow.subtitle(categoryName: nil, accountName: "HDFC")
    XCTAssertTrue(subtitle.contains("Uncategorized"))
  }

  // MARK: - M6: UPI surfacing

  func testSubtitleAppendsVPAAsThirdSegmentWhenPresent() {
    let subtitle = TransactionRow.subtitle(categoryName: "Food", accountName: "HDFC", vpa: "swiggy@okhdfc")
    XCTAssertEqual(subtitle, "Food · HDFC · swiggy@okhdfc")
  }

  func testSubtitleOmitsThirdSegmentWhenVPAIsNil() {
    let subtitle = TransactionRow.subtitle(categoryName: "Food", accountName: "HDFC", vpa: nil)
    XCTAssertEqual(subtitle, "Food · HDFC")
  }

  // MARK: - U18: currency symbol carries the code, not a trailing suffix

  /// The amount without its sign: integer and decimals joined.
  private func digits(_ parts: NomiAmountParts) -> String {
    parts.integer + parts.decimals
  }

  func testAmountPartsForAUSDRowCarryNoRupeeSymbolAndNoTrailingCode() {
    let text = digits(TransactionRow.amountParts(minor: 1299, direction: .debit, currencyCode: "USD"))
    XCTAssertFalse(text.contains("₹"))
    XCTAssertFalse(text.hasSuffix(" USD"))
    XCTAssertEqual(text, NomiFormatters.amountString(minor: 1299, currencyCode: "USD"))
  }

  func testAmountPartsOmitTheSuffixForINR() {
    let text = digits(TransactionRow.amountParts(minor: 1299, direction: .debit, currencyCode: "INR"))
    XCTAssertEqual(text, NomiFormatters.amountString(minor: 1299))
  }

  func testAmountPartsDefaultToINRWhenCurrencyCodeOmitted() {
    let withDefault = TransactionRow.amountParts(minor: 1299, direction: .debit)
    let withExplicitINR = TransactionRow.amountParts(minor: 1299, direction: .debit, currencyCode: "INR")
    XCTAssertEqual(withDefault, withExplicitINR)
  }

  // MARK: - LG: debit ink and credit ink (DEC-03)

  /// Lim's mutant M3 swapped these two and survived. Pinning the mapping
  /// directly fails on any swap.
  func testDebitAmountIsInk() {
    XCTAssertEqual(TransactionRow.amountInk(for: .debit), .ink)
  }

  func testCreditAmountIsInkDeep() {
    XCTAssertEqual(TransactionRow.amountInk(for: .credit), .inkDeep)
  }

  func testEachInkResolvesToItsToken() {
    XCTAssertEqual(TransactionRow.AmountInk.ink.color, NomiColor.ink)
    XCTAssertEqual(TransactionRow.AmountInk.inkDeep.color, NomiColor.inkDeep)
  }

  func testUPIKindCapsuleTextForP2P() {
    XCTAssertEqual(TransactionRow.upiKindCapsuleText(for: "p2p"), "P2P")
  }

  func testUPIKindCapsuleTextForP2M() {
    XCTAssertEqual(TransactionRow.upiKindCapsuleText(for: "p2m"), "Merchant")
  }

  func testUPIKindCapsuleTextIsNilForNonUPIRow() {
    XCTAssertNil(TransactionRow.upiKindCapsuleText(for: nil))
  }

  // MARK: - M4: title fallback

  func testTitlePrefersMerchantName() {
    let title = TransactionRow.title(merchantName: "Swiggy", descriptionText: "DINE OUT/SWIGGY", categoryName: "Food")
    XCTAssertEqual(title, "Swiggy")
  }

  func testTitleFallsBackToDescriptionWhenMerchantIsNil() {
    let title = TransactionRow.title(merchantName: nil, descriptionText: "UPI/P2A/RAHUL", categoryName: "Food")
    XCTAssertEqual(title, "UPI/P2A/RAHUL")
  }

  func testTitleFallsBackToCategoryNameForBlankDescription() {
    let title = TransactionRow.title(merchantName: nil, descriptionText: "   ", categoryName: "Food & Dining")
    XCTAssertEqual(title, "Food & Dining")
  }

  func testTitleFallsBackToManualEntryWhenEverythingIsBlank() {
    let title = TransactionRow.title(merchantName: nil, descriptionText: "", categoryName: nil)
    XCTAssertEqual(title, "Manual entry")
  }

  // MARK: - LG: signed amounts (DEC-03 / A-03.2)

  func testDebitPartsCarryAUnicodeMinusSign() {
    let parts = TransactionRow.amountParts(minor: 648_00, direction: .debit)
    XCTAssertEqual(parts.sign, "\u{2212}")
    XCTAssertEqual(parts.integer + parts.decimals, NomiFormatters.amountString(minor: 648_00))
  }

  func testCreditPartsCarryAPlusSign() {
    let parts = TransactionRow.amountParts(minor: 38_500_00, direction: .credit)
    XCTAssertEqual(parts.sign, "+")
  }

  func testZeroCarriesNoSignInEitherDirection() {
    XCTAssertEqual(TransactionRow.amountParts(minor: 0, direction: .debit).sign, "")
    XCTAssertEqual(TransactionRow.amountParts(minor: 0, direction: .credit).sign, "")
  }

  func testNegativeStoredMinorStillPrintsOneMinusForADebit() {
    let parts = TransactionRow.amountParts(minor: -1_299, direction: .debit)
    XCTAssertEqual(parts.sign, "\u{2212}")
    XCTAssertFalse(parts.integer.contains("\u{2212}"))
  }

  func testLakhValueDebitSplitsIntegerAndDecimals() {
    let parts = TransactionRow.amountParts(minor: 1_148_00, direction: .debit)
    XCTAssertEqual(parts.sign, "\u{2212}")
    XCTAssertTrue(parts.decimals.hasSuffix("00"))
  }

  // MARK: - LG: one accessibility element with a direction word

  func testDebitLabelSaysDebitAndNeverMinus() {
    let label = TransactionRow.accessibilityLabel(
      title: "Swiggy", subtitle: "Food · HDFC", direction: .debit, minor: 648_00,
      upiKind: nil, needsReview: false, mergedSourceCount: nil
    )
    XCTAssertTrue(label.contains("debit"))
    XCTAssertFalse(label.contains("credit"))
    XCTAssertFalse(label.contains("\u{2212}"))
    XCTAssertTrue(label.hasPrefix("Swiggy, Food · HDFC, debit, "))
  }

  func testCreditLabelSaysCredit() {
    let label = TransactionRow.accessibilityLabel(
      title: "Acme Payroll", subtitle: "Salary", direction: .credit, minor: 38_500_00,
      upiKind: nil, needsReview: false, mergedSourceCount: nil
    )
    XCTAssertTrue(label.contains("credit"))
    XCTAssertFalse(label.contains("debit"))
  }

  func testLabelAddsReviewAndMergeFactsWhenPresent() {
    let label = TransactionRow.accessibilityLabel(
      title: "Amazon", subtitle: "Uncategorized", direction: .debit, minor: 1_299_00,
      upiKind: "Merchant", needsReview: true, mergedSourceCount: 2
    )
    XCTAssertTrue(label.hasSuffix("Merchant, Merged from 2 sources, Needs review"))
  }

  // MARK: - LG: uncategorized initials

  func testInitialsTakeFirstLetterOfTwoWords() {
    XCTAssertEqual(TransactionRow.initials(for: "Acme Payroll"), "AP")
  }

  func testInitialsTakeTwoLettersOfOneWord() {
    XCTAssertEqual(TransactionRow.initials(for: "Amazon"), "AM")
  }

  func testInitialsAreUppercased() {
    XCTAssertEqual(TransactionRow.initials(for: "swiggy"), "SW")
  }

  func testInitialsIgnoreExtraWhitespace() {
    XCTAssertEqual(TransactionRow.initials(for: "  Manual   entry "), "ME")
  }
}
