import NomiCore
import XCTest
@testable import NomiUI

final class TransactionRowTests: XCTestCase {
  func testNilAccountRendersUnassigned() {
    let transaction = Transaction(descriptionText: "TEST", amountMinor: 100, accountID: nil)
    let row = TransactionRow(transaction: transaction, categoryName: "Food", accountName: nil)
    XCTAssertTrue(row.subtitleForTesting.contains("Unassigned"))
  }

  func testNilCategoryRendersUncategorized() {
    let transaction = Transaction(descriptionText: "TEST", amountMinor: 100)
    let row = TransactionRow(transaction: transaction, categoryName: nil, accountName: "HDFC")
    XCTAssertTrue(row.subtitleForTesting.contains("Uncategorized"))
  }

  func testCreditGetsPlusPrefix() {
    let transaction = Transaction(descriptionText: "TEST", amountMinor: 100, directionRaw: Direction.credit.rawValue)
    let row = TransactionRow(transaction: transaction, categoryName: nil, accountName: nil)
    XCTAssertTrue(row.amountTextForTesting.hasPrefix("+"))
  }

  func testDebitHasNoSignPrefix() {
    let transaction = Transaction(descriptionText: "TEST", amountMinor: 100, directionRaw: Direction.debit.rawValue)
    let row = TransactionRow(transaction: transaction, categoryName: nil, accountName: nil)
    XCTAssertFalse(row.amountTextForTesting.hasPrefix("+"))
  }
}
