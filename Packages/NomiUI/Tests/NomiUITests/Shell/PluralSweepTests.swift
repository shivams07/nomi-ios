import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// F6b. The remaining count copy goes through the catalog's plural variations,
/// and each site must read correctly for 0, 1 and 2. Each test calls the pure
/// function that owns the sentence, so the copy is pinned where it is built.
final class PluralSweepTests: XCTestCase {

  // MARK: Accounts row count

  func testAccountRowTransactionCountReadsForZeroOneAndTwo() {
    XCTAssertEqual(
      AccountRowText.subtitle(institution: "HDFC Bank", lastFour: "4471", transactionCount: 0),
      "HDFC Bank ••4471 · 0 transactions"
    )
    XCTAssertEqual(
      AccountRowText.subtitle(institution: "HDFC Bank", lastFour: "4471", transactionCount: 1),
      "HDFC Bank ••4471 · 1 transaction"
    )
    XCTAssertEqual(
      AccountRowText.subtitle(institution: "HDFC Bank", lastFour: "4471", transactionCount: 2),
      "HDFC Bank ••4471 · 2 transactions"
    )
  }

  func testWalletRowTransactionCountReadsWithoutLastFour() {
    XCTAssertEqual(
      AccountRowText.subtitle(institution: "Paytm", lastFour: "", transactionCount: 1),
      "Paytm · 1 transaction"
    )
  }

  // MARK: Account delete message

  func testAccountDeleteMessageReadsForZeroOneAndTwo() {
    XCTAssertEqual(
      AccountDeleteConfirmation.message(transactionCount: 0),
      "It has no transactions. This can't be undone."
    )
    XCTAssertEqual(
      AccountDeleteConfirmation.message(transactionCount: 1),
      "Its 1 transaction will be kept, unassigned from any account. This can't be undone."
    )
    XCTAssertEqual(
      AccountDeleteConfirmation.message(transactionCount: 2),
      "Its 2 transactions will be kept, unassigned from any account. This can't be undone."
    )
  }

  // MARK: Transaction detail merged sources

  func testMergedSourcesReadsForZeroOneAndTwo() {
    XCTAssertEqual(TransactionDetailLogic.mergedSourcesText(0), "Merged from 0 sources")
    XCTAssertEqual(TransactionDetailLogic.mergedSourcesText(1), "Merged from 1 source")
    XCTAssertEqual(TransactionDetailLogic.mergedSourcesText(2), "Merged from 2 sources")
  }

  func testFlagReasonsMergedLineReadsForTwo() {
    let reasons = TransactionDetailLogic.flagReasons(
      accountID: UUID(), needsReview: false, mergedCount: 2, isTransfer: false
    )
    XCTAssertEqual(reasons, ["Merged from 2 sources"])
  }

  // MARK: Transaction detail "You filed" caption

  func testMerchantHistoryReasonReadsForZeroOneAndTwo() {
    XCTAssertEqual(
      SuggestionRow.reasonText(reason: .merchantHistory(matches: 0), merchantLabel: "Swiggy", categoryName: "Food & Dining"),
      "You filed Swiggy as Food & Dining 0 times"
    )
    XCTAssertEqual(
      SuggestionRow.reasonText(reason: .merchantHistory(matches: 1), merchantLabel: "Swiggy", categoryName: "Food & Dining"),
      "You filed Swiggy as Food & Dining 1 time"
    )
    XCTAssertEqual(
      SuggestionRow.reasonText(reason: .merchantHistory(matches: 2), merchantLabel: "Swiggy", categoryName: "Food & Dining"),
      "You filed Swiggy as Food & Dining 2 times"
    )
  }

  // MARK: Backfill cancelled line

  func testBackfillCancelledLineReadsForZeroOneAndTwo() {
    XCTAssertEqual(
      BackfillLifecycle.cancelledText(created: 0),
      "0 transactions found so far. You can pick this up any time."
    )
    XCTAssertEqual(
      BackfillLifecycle.cancelledText(created: 1),
      "1 transaction found so far. You can pick this up any time."
    )
    XCTAssertEqual(
      BackfillLifecycle.cancelledText(created: 2),
      "2 transactions found so far. You can pick this up any time."
    )
  }

  // MARK: Backfill completion counts

  func testBackfillCompletionCountsReadForZeroOneAndTwo() {
    XCTAssertEqual(completionCounts(scanned: 0, created: 0), ["0 emails scanned", "0 transactions found"])
    XCTAssertEqual(completionCounts(scanned: 1, created: 1), ["1 email scanned", "1 transaction found"])
    XCTAssertEqual(completionCounts(scanned: 2, created: 2), ["2 emails scanned", "2 transactions found"])
  }

  private func completionCounts(scanned: Int, created: Int) -> [String] {
    let summary = SyncSummary(
      scanned: scanned, created: created, merged: 0, flagged: 0,
      packMatched: 0, heuristicMatched: 0, unmatchedSenders: []
    )
    return Array(BackfillCompletionSummary.lines(for: summary).prefix(2))
  }
}
