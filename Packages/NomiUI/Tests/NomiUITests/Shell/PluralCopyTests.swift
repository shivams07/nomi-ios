import XCTest

@testable import NomiUI

/// F6a. Every count in the owned copy goes through the catalog's plural
/// variations, so 0, 1 and 2 must each read correctly. The English catalog
/// lives in `Resources/Localizable.xcstrings`; these tests fail if a key is
/// missing or a plural variation is dropped, because the raw key would come
/// back instead of the sentence.
final class PluralCopyTests: XCTestCase {

  // MARK: Subscriptions header

  func testSubscriptionCountReadsForZeroOneAndTwo() {
    XCTAssertEqual(SubscriptionsSummary.countText(0), "0 subscriptions")
    XCTAssertEqual(SubscriptionsSummary.countText(1), "1 subscription")
    XCTAssertEqual(SubscriptionsSummary.countText(2), "2 subscriptions")
  }

  // MARK: Subscriptions next-charge caption

  func testNextInDaysReadsForOneAndTwo() {
    let now = Date()
    let oneOut = Calendar.current.date(byAdding: .day, value: 1, to: now)!
    let twoOut = Calendar.current.date(byAdding: .day, value: 2, to: now)!

    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: oneOut, now: now), "next in 1 day")
    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: twoOut, now: now), "next in 2 days")
  }

  func testExpectedDaysAgoReadsForOneAndTwo() {
    let now = Date()
    let oneAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
    let twoAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: oneAgo, now: now), "expected 1 day ago")
    XCTAssertEqual(SubscriptionRowText.nextCharge(nextExpected: twoAgo, now: now), "expected 2 days ago")
  }

  // MARK: Budgets days-left

  func testBudgetsDaysLeftReadsForZeroOneAndTwo() {
    XCTAssertEqual(BudgetPeriodText.daysLeft(0), "0 days")
    XCTAssertEqual(BudgetPeriodText.daysLeft(1), "1 day")
    XCTAssertEqual(BudgetPeriodText.daysLeft(2), "2 days")
  }

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
