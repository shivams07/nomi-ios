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
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: false, mergedCount: 1, isTransfer: false), [])
  }

  func testFlagReasonsNoAccountOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: nil, needsReview: false, mergedCount: 1, isTransfer: false),
      ["No account assigned"])
  }

  func testFlagReasonsNeedsReviewOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: true, mergedCount: 1, isTransfer: false),
      ["Needs review"])
  }

  func testFlagReasonsMergedOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: false, mergedCount: 2, isTransfer: false),
      ["Merged from 2 sources"])
  }

  func testFlagReasonsAllThreeInFixedOrder() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: nil, needsReview: true, mergedCount: 3, isTransfer: false),
      ["No account assigned", "Needs review", "Merged from 3 sources"])
  }

  /// DEC-05 T3: a transfer is a flag on Detail, and it is the last one.
  func testFlagReasonsTransferOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: UUID(), needsReview: false, mergedCount: 1, isTransfer: true),
      ["Transfer"])
  }

  func testFlagReasonsTransferComesLastInFixedOrder() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(accountID: nil, needsReview: true, mergedCount: 2, isTransfer: true),
      ["No account assigned", "Needs review", "Merged from 2 sources", "Transfer"])
  }

  // MARK: - DEC-05 T3: transfer copy

  /// The two sentences are fixed copy from the plan, pinned word for word.
  func testTransferSentenceIsTheSpecifiedCopy() {
    XCTAssertEqual(
      TransactionDetailLogic.transferSentence,
      "Not counted as spending or income. This moves money between your own accounts.")
  }

  func testNoMatchSentenceIsTheSpecifiedCopy() {
    XCTAssertEqual(
      TransactionDetailLogic.noMatchSentence,
      "No matching payment found on another account. Only this transaction is excluded.")
  }

  /// The action reads `isTransfer` alone. A swapped ternary offers the wrong action.
  func testTransferButtonOffersMarkForAnUnmarkedRow() {
    XCTAssertEqual(TransactionDetailLogic.transferButtonTitle(isTransfer: false), "Mark as transfer")
  }

  func testTransferButtonOffersUnmarkForAMarkedRow() {
    XCTAssertEqual(TransactionDetailLogic.transferButtonTitle(isTransfer: true), "Not a transfer")
  }

  func testMarkOutcomeWithNoPartnerSaysOnlyThisTransactionIsExcluded() {
    XCTAssertEqual(
      TransactionDetailLogic.markOutcome(partner: nil),
      "No matching payment found on another account. Only this transaction is excluded.")
  }

  /// The partner's narration and its own date both appear, and the date is
  /// formatted as Detail formats every date.
  func testMarkOutcomeNamesThePartnerAndItsDate() {
    let date = Date(timeIntervalSince1970: 1_794_326_400)
    let partner = TransactionDetailLogic.TransferPartner(narration: "HDFC CREDIT CARD PAYMENT", date: date)
    XCTAssertEqual(
      TransactionDetailLogic.markOutcome(partner: partner),
      "Also marked: HDFC CREDIT CARD PAYMENT, \(NomiFormatters.dayMonthYear.string(from: date))")
  }

  func testUnmarkOutcomeWithNoPartnerSaysTheRowCountsAgain() {
    XCTAssertEqual(
      TransactionDetailLogic.unmarkOutcome(partner: nil), "Now counted as spending or income again.")
  }

  /// Unmarking clears the partner too, so the copy must name it and say both count again.
  func testUnmarkOutcomeNamesThePartnerThatCountsAgain() {
    let date = Date(timeIntervalSince1970: 1_794_326_400)
    let partner = TransactionDetailLogic.TransferPartner(narration: "RAZORPAY CC PAYMENT", date: date)
    XCTAssertEqual(
      TransactionDetailLogic.unmarkOutcome(partner: partner),
      "Also unmarked: RAZORPAY CC PAYMENT, \(NomiFormatters.dayMonthYear.string(from: date)). Both now count as spending or income.")
  }

  /// A partner whose narration is blank still reads as a sentence.
  func testMarkOutcomeNamesABlankNarrationAsAnotherTransaction() {
    let date = Date(timeIntervalSince1970: 1_794_326_400)
    let partner = TransactionDetailLogic.TransferPartner(narration: "   ", date: date)
    XCTAssertEqual(
      TransactionDetailLogic.markOutcome(partner: partner),
      "Also marked: another transaction, \(NomiFormatters.dayMonthYear.string(from: date))")
  }

  // MARK: - M6: UPIDisplay

  func testKindLabelForP2PIsPerson() {
    XCTAssertEqual(UPIDisplay.kindLabel("p2p"), "Person")
  }

  func testKindLabelForP2MIsMerchant() {
    XCTAssertEqual(UPIDisplay.kindLabel("p2m"), "Merchant")
  }

  func testKindLabelForAnUnknownRawValueIsNil() {
    XCTAssertNil(UPIDisplay.kindLabel("unknown"))
  }

  // MARK: - U24: noteToSave

  func testNoteToSavePassesThroughNonBlankText() {
    XCTAssertEqual(TransactionDetailLogic.noteToSave(from: "Split with Riya"), "Split with Riya")
  }

  func testNoteToSaveTrimsSurroundingWhitespace() {
    XCTAssertEqual(TransactionDetailLogic.noteToSave(from: "  Split with Riya  "), "Split with Riya")
  }

  func testNoteToSaveTreatsEmptyStringAsNoNote() {
    XCTAssertNil(TransactionDetailLogic.noteToSave(from: ""))
  }

  func testNoteToSaveTreatsWhitespaceOnlyAsNoNote() {
    XCTAssertNil(TransactionDetailLogic.noteToSave(from: "   \n  "))
  }

  // MARK: - M4: SuggestionRow

  func testIsShownFalseForNilSuggestion() {
    XCTAssertFalse(SuggestionRow.isShown(suggestion: nil, currentCategoryID: UUID(), categorySource: .rule))
  }

  func testIsShownFalseWhenCategorySourceIsManual() {
    let suggestion = CategorySuggestion(categoryID: UUID(), reason: .merchantHistory(matches: 4))
    XCTAssertFalse(SuggestionRow.isShown(suggestion: suggestion, currentCategoryID: UUID(), categorySource: .manual))
  }

  func testIsShownFalseWhenSuggestedIDEqualsCurrent() {
    let categoryID = UUID()
    let suggestion = CategorySuggestion(categoryID: categoryID, reason: .merchantHistory(matches: 4))
    XCTAssertFalse(SuggestionRow.isShown(suggestion: suggestion, currentCategoryID: categoryID, categorySource: .rule))
  }

  func testIsShownTrueOtherwise() {
    let suggestion = CategorySuggestion(categoryID: UUID(), reason: .merchantHistory(matches: 4))
    XCTAssertTrue(SuggestionRow.isShown(suggestion: suggestion, currentCategoryID: nil, categorySource: .none))
  }

  func testReasonTextForMerchantHistory() {
    let text = SuggestionRow.reasonText(
      reason: .merchantHistory(matches: 4), merchantLabel: "Swiggy", categoryName: "Food & Dining")
    XCTAssertEqual(text, "You filed Swiggy as Food & Dining 4 times")
  }

  func testReasonTextForMerchantHistorySingularMatch() {
    let text = SuggestionRow.reasonText(
      reason: .merchantHistory(matches: 1), merchantLabel: "Swiggy", categoryName: "Food & Dining")
    XCTAssertEqual(text, "You filed Swiggy as Food & Dining 1 time")
  }

  func testReasonTextForRule() {
    let text = SuggestionRow.reasonText(
      reason: .rule(ruleID: UUID()), merchantLabel: "Swiggy", categoryName: "Food & Dining")
    XCTAssertEqual(text, "Matches your rule for Swiggy")
  }

  // MARK: - DT: primaryAction truth table

  func testPrimaryIsApplyWhenSuggestionShownAndFlagged() {
    XCTAssertEqual(TransactionDetailLogic.primaryAction(hasSuggestion: true, needsReview: true), .apply)
  }

  func testPrimaryIsApplyWhenSuggestionShownAndNotFlagged() {
    XCTAssertEqual(TransactionDetailLogic.primaryAction(hasSuggestion: true, needsReview: false), .apply)
  }

  func testPrimaryIsMarkReviewedWhenFlaggedWithoutSuggestion() {
    XCTAssertEqual(TransactionDetailLogic.primaryAction(hasSuggestion: false, needsReview: true), .markReviewed)
  }

  func testPrimaryIsNoneWhenNeitherApplies() {
    XCTAssertEqual(TransactionDetailLogic.primaryAction(hasSuggestion: false, needsReview: false), .none)
  }

  // MARK: - DT: signedMinor (DEC-03 / A-03 sign rule)

  func testDebitIsNegativeAndCreditPositive() {
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: 68_00, direction: .debit), -68_00)
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: 38_500_00, direction: .credit), 38_500_00)
  }

  func testZeroCarriesNoSign() {
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: 0, direction: .debit), 0)
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: 0, direction: .credit), 0)
  }

  func testSignFollowsDirectionNotAStoredSign() {
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: -68_00, direction: .debit), -68_00)
    XCTAssertEqual(TransactionDetailLogic.signedMinor(amountMinor: -68_00, direction: .credit), 68_00)
  }
}
