import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// The First scan screen's copy and rows (S12c), pinned without a view. Counts are
/// kept under 1,000: the catalog plural groups thousands, so a count of 1,200 would
/// read "1,200" and these pins would be about grouping, not about the rows.
final class BackfillDisplayTests: XCTestCase {
  private func summary(
    institution: String,
    displayName: String = "Savings",
    lastFour: String = "4471",
    transactions: Int
  ) -> AccountSummary {
    AccountSummary(
      id: UUID(),
      displayName: displayName,
      institution: institution,
      lastFour: lastFour,
      kindRaw: "savings",
      trackedBalanceMinor: 0,
      transactionCount: transactions,
      trackingSince: nil,
      isArchived: false
    )
  }

  /// "title | detail" per row, so one assertion pins the order, the copy and the count.
  private func lines(_ rows: [(title: String, detail: String)]) -> [String] {
    rows.map { "\($0.title) | \($0.detail)" }
  }

  // MARK: - Found line and caption

  func testFoundLineCountsTransactionsInTheSingularAndPlural() {
    XCTAssertEqual(BackfillDisplay.foundLine(created: 1), "1 transaction found so far")
    XCTAssertEqual(BackfillDisplay.foundLine(created: 0), "0 transactions found so far")
    XCTAssertEqual(BackfillDisplay.foundLine(created: 214), "214 transactions found so far")
  }

  func testCaptionNamesTheWindowAndNoMonth() {
    XCTAssertEqual(BackfillDisplay.captionLine(months: 6), "Checking your last 6 months")
    XCTAssertEqual(BackfillDisplay.captionLine(months: 1), "Checking your last 1 month")
  }

  // MARK: - Account rows

  func testRowsSortAccountsByTransactionCountDescending() {
    let rows = BackfillDisplay.rows(
      summaries: [
        summary(institution: "ICICI Credit Card", lastFour: "9012", transactions: 68),
        summary(institution: "HDFC Bank", transactions: 142),
        summary(institution: "Axis Bank", lastFour: "1200", transactions: 9),
      ],
      needsReview: 0
    )

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 142 alerts",
      "ICICI Credit Card ••9012 | 68 alerts",
      "Axis Bank ••1200 | 9 alerts",
    ])
  }

  func testRowsLeaveOutAccountsWithNoTransactions() {
    let rows = BackfillDisplay.rows(
      summaries: [
        summary(institution: "HDFC Bank", transactions: 0),
        summary(institution: "ICICI Credit Card", lastFour: "9012", transactions: 3),
      ],
      needsReview: 0
    )

    XCTAssertEqual(lines(rows), ["ICICI Credit Card ••9012 | 3 alerts"])
  }

  func testATieOnCountOrdersByTitle() {
    let rows = BackfillDisplay.rows(
      summaries: [
        summary(institution: "ICICI Credit Card", lastFour: "9012", transactions: 5),
        summary(institution: "HDFC Bank", transactions: 5),
      ],
      needsReview: 0
    )

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 5 alerts",
      "ICICI Credit Card ••9012 | 5 alerts",
    ])
  }

  func testAOneTransactionAccountReadsAsOneAlert() {
    let rows = BackfillDisplay.rows(
      summaries: [summary(institution: "HDFC Bank", transactions: 1)],
      needsReview: 0
    )

    XCTAssertEqual(lines(rows), ["HDFC Bank ••4471 | 1 alert"])
  }

  func testATitleFallsBackToTheAccountNameWhenThereIsNoInstitution() {
    let rows = BackfillDisplay.rows(
      summaries: [summary(institution: "", displayName: "Cash wallet", lastFour: "", transactions: 2)],
      needsReview: 0
    )

    XCTAssertEqual(lines(rows), ["Cash wallet | 2 alerts"])
  }

  // MARK: - Need a look

  func testNeedALookIsTheLastRowWhenSomethingWaitsForReview() {
    let rows = BackfillDisplay.rows(
      summaries: [summary(institution: "HDFC Bank", transactions: 142)],
      needsReview: 4
    )

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 142 alerts",
      "Need a look | 4 to check",
    ])
  }

  func testNeedALookReadsAsOneToCheckForOne() {
    let rows = BackfillDisplay.rows(summaries: [], needsReview: 1)

    XCTAssertEqual(lines(rows), ["Need a look | 1 to check"])
  }

  func testNoNeedALookRowWhenNothingNeedsReview() {
    let rows = BackfillDisplay.rows(
      summaries: [summary(institution: "HDFC Bank", transactions: 142)],
      needsReview: 0
    )

    XCTAssertFalse(rows.contains { $0.title == "Need a look" })
  }

  func testNoRowsWhenThereAreNoAccountsAndNothingToCheck() {
    XCTAssertTrue(BackfillDisplay.rows(summaries: [], needsReview: 0).isEmpty)
  }

  // MARK: - Three rows in total

  private var fourAccounts: [AccountSummary] {
    [
      summary(institution: "HDFC Bank", lastFour: "4471", transactions: 142),
      summary(institution: "ICICI Credit Card", lastFour: "9012", transactions: 68),
      summary(institution: "Axis Bank", lastFour: "1200", transactions: 9),
      summary(institution: "Kotak", lastFour: "7755", transactions: 4),
    ]
  }

  func testWithNothingToReviewTheAccountsFillAllThreeRows() {
    let rows = BackfillDisplay.rows(summaries: fourAccounts, needsReview: 0)

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 142 alerts",
      "ICICI Credit Card ••9012 | 68 alerts",
      "Axis Bank ••1200 | 9 alerts",
    ])
  }

  func testNeedALookKeepsItsRowWhenAccountsWouldFillThree() {
    let rows = BackfillDisplay.rows(summaries: fourAccounts, needsReview: 4)

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 142 alerts",
      "ICICI Credit Card ••9012 | 68 alerts",
      "Need a look | 4 to check",
    ])
  }

  func testNeedALookTakesTheThirdSlotWhenThereAreThreeAccounts() {
    let rows = BackfillDisplay.rows(
      summaries: Array(fourAccounts.prefix(3)),
      needsReview: 1
    )

    XCTAssertEqual(lines(rows), [
      "HDFC Bank ••4471 | 142 alerts",
      "ICICI Credit Card ••9012 | 68 alerts",
      "Need a look | 1 to check",
    ])
  }

  func testTheRowsNeverExceedThree() {
    XCTAssertEqual(BackfillDisplay.rows(summaries: fourAccounts, needsReview: 0).count, 3)
    XCTAssertEqual(BackfillDisplay.rows(summaries: fourAccounts, needsReview: 2).count, 3)
  }
}
