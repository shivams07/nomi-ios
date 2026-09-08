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

  func testCreditGetsPlusPrefix() {
    let text = TransactionRow.amountText(minor: 100, direction: .credit)
    XCTAssertTrue(text.hasPrefix("+"))
  }

  func testDebitHasNoSignPrefix() {
    let text = TransactionRow.amountText(minor: 100, direction: .debit)
    XCTAssertFalse(text.hasPrefix("+"))
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

  func testAmountTextForAUSDRowCarriesNoRupeeSymbolAndNoTrailingCode() {
    let text = TransactionRow.amountText(minor: 1299, direction: .debit, currencyCode: "USD")
    XCTAssertFalse(text.contains("₹"))
    XCTAssertFalse(text.hasSuffix(" USD"))
    XCTAssertEqual(text, NomiFormatters.amountString(minor: 1299, currencyCode: "USD"))
  }

  func testAmountTextOmitsSuffixForINR() {
    let text = TransactionRow.amountText(minor: 1299, direction: .debit, currencyCode: "INR")
    XCTAssertEqual(text, NomiFormatters.amountString(minor: 1299))
  }

  func testAmountTextDefaultsToINRWhenCurrencyCodeOmitted() {
    let withDefault = TransactionRow.amountText(minor: 1299, direction: .debit)
    let withExplicitINR = TransactionRow.amountText(minor: 1299, direction: .debit, currencyCode: "INR")
    XCTAssertEqual(withDefault, withExplicitINR)
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
}
