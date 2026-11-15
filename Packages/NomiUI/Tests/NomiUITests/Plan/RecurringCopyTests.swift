import Foundation
import XCTest

@testable import NomiUI

/// The verb on a recurring row (S7). "Due" for the bills a household must pay,
/// "Renews" for everything else, "Next" when the run has no category.
final class RecurringCopyTests: XCTestCase {
  func testEachDueKeywordReadsAsDue() {
    for name in ["Rent", "EMI", "Home Loan", "Insurance", "Utilities", "Electricity bill"] {
      XCTAssertEqual(RecurringCopy.verb(categoryName: name), "Due", name)
    }
  }

  func testMatchingIgnoresCase() {
    XCTAssertEqual(RecurringCopy.verb(categoryName: "RENT"), "Due")
    XCTAssertEqual(RecurringCopy.verb(categoryName: "bIlLs & Utilities"), "Due")
  }

  func testAnyOtherCategoryRenews() {
    for name in ["Subscriptions", "Entertainment", "Shopping", ""] {
      XCTAssertEqual(RecurringCopy.verb(categoryName: name), "Renews", name)
    }
  }

  func testNoCategoryIsNext() {
    XCTAssertEqual(RecurringCopy.verb(categoryName: nil), "Next")
  }
}
