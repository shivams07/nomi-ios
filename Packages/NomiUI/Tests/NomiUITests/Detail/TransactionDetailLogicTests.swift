import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class TransactionDetailLogicTests: XCTestCase {

  // MARK: - availableActions

  func testFlaggedRowIncludesMarkReviewed() {
    XCTAssertTrue(TransactionDetailLogic.availableActions(needsReview: true).contains(.markReviewed))
  }

  func testUnflaggedRowExcludesMarkReviewed() {
    XCTAssertFalse(TransactionDetailLogic.availableActions(needsReview: false).contains(.markReviewed))
  }

  func testEveryRowGetsTheBaseSectionsAndDelete() {
    for needsReview in [true, false] {
      let actions = Set(TransactionDetailLogic.availableActions(needsReview: needsReview))
      XCTAssertTrue(actions.isSuperset(of: [.category, .account, .edit, .source, .delete]))
    }
  }

  // MARK: - sourceSummary

  func testSourceSummaryOneLinePerRefInOrder() {
    let refs = [
      SourceRef(source: .email, externalID: "uid-1", capturedAt: Date(timeIntervalSince1970: 0)),
      SourceRef(source: .file, externalID: "csv-9", capturedAt: Date(timeIntervalSince1970: 0)),
    ]
    XCTAssertEqual(TransactionDetailLogic.sourceSummary(refs: refs), ["Email · uid-1", "File · csv-9"])
  }

  func testSourceSummaryEmptyForNoRefs() {
    XCTAssertEqual(TransactionDetailLogic.sourceSummary(refs: []), [])
  }

  // MARK: - flagReasons

  func testFlagReasonsNoneWhenNothingIsWrong() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: false, mergedCount: 1), [])
  }

  func testFlagReasonsNoAccountOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: nil, needsReview: false, mergedCount: 1),
      ["No account assigned"])
  }

  func testFlagReasonsNeedsReviewOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: true, mergedCount: 1),
      ["Needs review"])
  }

  func testFlagReasonsMergedOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: false, mergedCount: 2),
      ["Merged from 2 sources"])
  }

  func testFlagReasonsAllThreeInFixedOrder() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: nil, needsReview: true, mergedCount: 3),
      ["No account assigned", "Needs review", "Merged from 3 sources"])
  }
}
