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
}
