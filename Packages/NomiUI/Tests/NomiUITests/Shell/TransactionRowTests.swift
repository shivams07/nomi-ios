import NomiCore
import XCTest
@testable import NomiUI

/// Exercises `TransactionRow`'s pure display-logic helpers only. This package's
/// CI runner cannot construct `@Model` instances headlessly (SwiftData's
/// bundle-name resolution fails outside an app bundle — see
/// `InMemoryModelContainer`'s note in NomiCore), so these tests never build a
/// `Transaction`.
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

  func testAmountTextAppendsNonINRCurrencyCode() {
    let text = TransactionRow.amountText(minor: 1299, direction: .debit, currencyCode: "USD")
    XCTAssertTrue(text.hasSuffix(" USD"))
    XCTAssertTrue(text.contains(NomiFormatters.amountString(minor: 1299)))
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
}
