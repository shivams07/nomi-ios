import XCTest

@testable import NomiUI

/// F6a. Every count in the owned copy goes through the catalog's plural
/// variations, so 0, 1 and 2 must each read correctly. The English catalog
/// lives in `Resources/Localizable.xcstrings`; these tests fail if a key is
/// missing or a plural variation is dropped, because the raw key would come
/// back instead of the sentence.
final class PluralCopyTests: XCTestCase {

  // MARK: Needs-you card line

  func testNeedsReviewLineReadsForOneAndTwo() {
    XCTAssertEqual(
      NeedsYouText.line(needsReviewCount: 1, uncategorizedCount: 0),
      "1 transaction to review"
    )
    XCTAssertEqual(
      NeedsYouText.line(needsReviewCount: 2, uncategorizedCount: 0),
      "2 transactions to review"
    )
  }

  func testUncategorizedLineReadsForOneAndTwo() {
    XCTAssertEqual(
      NeedsYouText.line(needsReviewCount: 0, uncategorizedCount: 1),
      "1 uncategorized transaction"
    )
    XCTAssertEqual(
      NeedsYouText.line(needsReviewCount: 0, uncategorizedCount: 2),
      "2 uncategorized transactions"
    )
  }
}
