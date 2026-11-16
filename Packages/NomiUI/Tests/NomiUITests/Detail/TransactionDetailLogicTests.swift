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

  // MARK: - WR-2 (G2): stored review reason

  /// Each stored reason has exactly its audit wording on the Detail chip.
  func testReviewReasonTextCoversEveryCase() {
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.unauthenticatedSender), "Sender not verified")
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.foreignCurrency), "Not in rupees, not counted")
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.unreadableDate), "Date couldn't be read")
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.unparseable), "Amount couldn't be read")
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.heuristic), "Read from an unfamiliar email")
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(.unidentifiedAccount), "Needs review")
  }

  /// A row with no stored reason keeps the bare symptom the screen always showed.
  func testReviewReasonTextForNilKeepsNeedsReview() {
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(nil), "Needs review")
  }

  /// A raw value this build does not know reads as nil through the model's
  /// accessor, so it must fall back to the same bare text.
  func testReviewReasonTextForAnUnknownRawValueKeepsNeedsReview() {
    let reason = NeedsReviewReason(rawValue: "someFutureCase")
    XCTAssertNil(reason)
    XCTAssertEqual(TransactionDetailLogic.reviewReasonText(reason), "Needs review")
  }

  /// The wording is for a person: no chip shows a Swift case name or a raw value.
  func testReviewReasonTextNeverShowsARawCaseName() {
    let rawValues = [
      NeedsReviewReason.unauthenticatedSender, .foreignCurrency, .unreadableDate,
      .unparseable, .heuristic, .unidentifiedAccount,
    ].map(\.rawValue)
    for reason in [NeedsReviewReason.unauthenticatedSender, .foreignCurrency, .unreadableDate, .unparseable, .heuristic] {
      let text = TransactionDetailLogic.reviewReasonText(reason)
      for raw in rawValues {
        XCTAssertFalse(text.contains(raw), "\(text) shows \(raw)")
      }
    }
  }

  func testFlagReasonsUsesStoredReasonWhenFlagged() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(
        accountID: UUID(), needsReview: true, mergedCount: 1, isTransfer: false,
        needsReviewReason: .unauthenticatedSender),
      ["Sender not verified"])
  }

  /// Dismissing a row leaves the stored reason in place, and it must not come back.
  func testFlagReasonsIgnoresReasonWhenNotFlagged() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(
        accountID: UUID(), needsReview: false, mergedCount: 1, isTransfer: false,
        needsReviewReason: .foreignCurrency),
      [])
  }

  func testFlagReasonsWithoutAStoredReasonKeepsNeedsReview() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(
        accountID: UUID(), needsReview: true, mergedCount: 1, isTransfer: false),
      ["Needs review"])
  }

  /// The stored reason takes the "Needs review" slot, so the fixed order holds.
  func testFlagReasonsStoredReasonKeepsFixedOrder() {
    XCTAssertEqual(
      TransactionDetailLogic.flagReasons(
        accountID: nil, needsReview: true, mergedCount: 2, isTransfer: true,
        needsReviewReason: .foreignCurrency),
      ["No account assigned", "Not in rupees, not counted", "Merged from 2 sources", "Transfer"])
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

  // MARK: - D7: where Mark reviewed is drawn

  func testFlaggedRowWithoutSuggestionPutsMarkReviewedPrimaryUnderCategory() {
    let primary = TransactionDetailLogic.primaryAction(hasSuggestion: false, needsReview: true)
    XCTAssertEqual(
      TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: true), .primaryUnderCategory)
  }

  func testFlaggedRowWithSuggestionKeepsMarkReviewedSecondaryInLargeDetails() {
    let primary = TransactionDetailLogic.primaryAction(hasSuggestion: true, needsReview: true)
    XCTAssertEqual(
      TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: true), .secondaryInLargeDetails)
  }

  func testUnflaggedRowNeverShowsMarkReviewed() {
    for hasSuggestion in [false, true] {
      let primary = TransactionDetailLogic.primaryAction(hasSuggestion: hasSuggestion, needsReview: false)
      XCTAssertEqual(
        TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: false), .hidden,
        "hasSuggestion \(hasSuggestion)")
    }
  }

  func testMarkReviewedIsDrawnAtExactlyOneSpotForEveryFlagCombination() {
    for hasSuggestion in [false, true] {
      for needsReview in [false, true] {
        let primary = TransactionDetailLogic.primaryAction(hasSuggestion: hasSuggestion, needsReview: needsReview)
        let placement = TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: needsReview)
        // Flagged rows always get exactly one spot; the no-suggestion primary is never also in large details.
        if needsReview {
          XCTAssertNotEqual(placement, .hidden, "hasSuggestion \(hasSuggestion)")
        } else {
          XCTAssertEqual(placement, .hidden, "hasSuggestion \(hasSuggestion)")
        }
        XCTAssertEqual(placement == .primaryUnderCategory, primary == .markReviewed)
      }
    }
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

  // MARK: - X12: category picker commit

  func testPickerCommitTruthTable() {
    let a = UUID()
    let b = UUID()
    // The picker only reports a nil pick when the user taps None (S3a opts in).
    // Clearing a categorised row writes nil; None on an uncategorised row is no change.
    XCTAssertEqual(CategoryPickCommit.decision(picked: nil, current: a), .clear)
    XCTAssertEqual(CategoryPickCommit.decision(picked: nil, current: nil), .keep)
    // Picking the category the row already has is not a change.
    XCTAssertEqual(CategoryPickCommit.decision(picked: a, current: a), .keep)
    // A different pick is a change.
    XCTAssertEqual(CategoryPickCommit.decision(picked: b, current: a), .set(b))
    // An uncategorised row takes its first pick.
    XCTAssertEqual(CategoryPickCommit.decision(picked: a, current: nil), .set(a))
  }

  /// S3a/S5 note (Lim, PR 207): the None row must clear the selection. The row
  /// is first in the picker when `allowsNone`, and its nil pick decides `.clear`.
  func testNoneRowLeadsThePickerAndClearsTheCategory() {
    let category = UUID()
    XCTAssertEqual(CategoryPickerLogic.rows(categoryIDs: [category], allowsNone: true), [.unset, .category(category)])
    XCTAssertEqual(CategoryPickerLogic.rows(categoryIDs: [category], allowsNone: false), [.category(category)])
    XCTAssertEqual(CategoryPickCommit.decision(picked: nil, current: category), .clear)
  }

  // MARK: - S3a: caption

  private var kolkata: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }

  private func kolkataDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    kolkata.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  func testCaptionForToday() {
    XCTAssertEqual(
      TransactionDetailLogic.caption(
        date: kolkataDate(13, 21, 42), now: kolkataDate(13, 18, 0), calendar: kolkata, accountName: "HDFC ••4471"),
      "Today, 13 Nov · 9:42 pm · HDFC ••4471")
  }

  func testCaptionForYesterday() {
    XCTAssertEqual(
      TransactionDetailLogic.caption(
        date: kolkataDate(13, 21, 42), now: kolkataDate(14, 10, 0), calendar: kolkata, accountName: "HDFC ••4471"),
      "Yesterday, 13 Nov · 9:42 pm · HDFC ••4471")
  }

  func testCaptionForAnOlderDayIsTheDayAndMonthOnly() {
    XCTAssertEqual(
      TransactionDetailLogic.caption(
        date: kolkataDate(11, 9, 5), now: kolkataDate(16, 10, 0), calendar: kolkata, accountName: "HDFC ••4471"),
      "11 Nov · 9:05 am · HDFC ••4471")
  }

  func testCaptionOmitsTheAccountWhenThereIsNone() {
    XCTAssertEqual(
      TransactionDetailLogic.caption(
        date: kolkataDate(13, 21, 42), now: kolkataDate(14, 10, 0), calendar: kolkata, accountName: nil),
      "Yesterday, 13 Nov · 9:42 pm")
  }

  func testCaptionTreatsABlankAccountAsNone() {
    XCTAssertEqual(
      TransactionDetailLogic.caption(
        date: kolkataDate(13, 21, 42), now: kolkataDate(14, 10, 0), calendar: kolkata, accountName: "  "),
      "Yesterday, 13 Nov · 9:42 pm")
  }

  // MARK: - S3a: delete confirmation

  func testDeleteConfirmationSentenceNamesAmountMerchantAndDay() {
    XCTAssertEqual(
      TransactionDetailLogic.deleteConfirmationSentence(
        amountText: "₹845.00", merchant: "Ola", date: kolkataDate(13, 21, 42), calendar: kolkata),
      "₹845.00 to Ola on 13 Nov will be removed from every total.")
  }

  // MARK: - S3a: rule row

  func testRuleRowShowsOnlyWithAStoreAPatternAndNoTransfer() {
    let cases: [(store: Bool, transfer: Bool, pattern: String?, shown: Bool)] = [
      (true, false, "*OLA*", true),
      (false, false, "*OLA*", false),
      (true, true, "*OLA*", false),
      (true, false, nil, false),
    ]
    for row in cases {
      XCTAssertEqual(
        TransactionDetailLogic.showsRuleRow(hasRuleStore: row.store, isTransfer: row.transfer, pattern: row.pattern),
        row.shown,
        "store \(row.store), transfer \(row.transfer), pattern \(String(describing: row.pattern))")
    }
  }

  func testRuleSwitchIsDisabledForAnUncategorisedRow() {
    XCTAssertFalse(TransactionDetailLogic.ruleSwitchEnabled(categoryID: nil))
    XCTAssertTrue(TransactionDetailLogic.ruleSwitchEnabled(categoryID: UUID()))
  }

  func testExistingRuleMatchesOnPatternAndCategoryOnly() {
    let food = UUID()
    let bills = UUID()
    let userRule = UUID()
    let rules: [TransactionDetailLogic.RuleRef] = [
      .init(id: UUID(), pattern: "*OLA*", categoryID: food, isSystem: true),
      .init(id: UUID(), pattern: "*AMAZON*", categoryID: food, isSystem: false),
      .init(id: UUID(), pattern: "*OLA*", categoryID: bills, isSystem: false),
      .init(id: userRule, pattern: "*OLA*", categoryID: food, isSystem: false),
    ]
    XCTAssertEqual(TransactionDetailLogic.existingRuleID(among: rules, pattern: "*OLA*", categoryID: food), userRule)
    XCTAssertNil(TransactionDetailLogic.existingRuleID(among: rules, pattern: "*OLA*", categoryID: UUID()))
    XCTAssertNil(TransactionDetailLogic.existingRuleID(among: [rules[0]], pattern: "*OLA*", categoryID: food))
  }

  // MARK: - S3a: category chip and copy

  func testCategoryChipTextReadsTransferForATransferLeg() {
    XCTAssertEqual(TransactionDetailLogic.categoryChipText(isTransfer: true, categoryName: "Food"), "Transfer")
    XCTAssertEqual(TransactionDetailLogic.categoryChipText(isTransfer: false, categoryName: "Food"), "Food")
    XCTAssertEqual(TransactionDetailLogic.categoryChipText(isTransfer: false, categoryName: nil), "Uncategorized")
  }

  /// S10's ruling: the count is what preview matches, so it says "match" and
  /// not "applies". Catalog plurals on 1 and 2+.
  func testMatchCountTextPluralisesAndSaysMatch() {
    XCTAssertEqual(TransactionDetailLogic.matchCountText(count: 1, isOn: true), "Matches 1 past transaction and all future ones")
    XCTAssertEqual(TransactionDetailLogic.matchCountText(count: 5, isOn: true), "Matches 5 past transactions and all future ones")
    XCTAssertEqual(TransactionDetailLogic.matchCountText(count: 0, isOn: false), "Matches 0 past transactions")
    XCTAssertEqual(TransactionDetailLogic.matchCountText(count: 2, isOn: false), "Matches 2 past transactions")
  }

  func testAppliedTextPluralises() {
    XCTAssertEqual(TransactionDetailLogic.appliedText(count: 1), "Applied to 1 transaction")
    XCTAssertEqual(TransactionDetailLogic.appliedText(count: 5), "Applied to 5 transactions")
  }

  // MARK: - S3a fix round (Lim, PR #220): the switch decides, then writes

  /// Turning the switch on creates the rule when none exists for this category.
  func testRuleSwitchOnWithNoRuleCreatesForTheCategory() {
    let category = UUID()
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(turningOn: true, existingRuleID: nil, categoryID: category),
      .create(categoryID: category))
  }

  /// Turning the switch on when the rule already exists writes nothing.
  func testRuleSwitchOnWithAnExistingRuleDoesNothing() {
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(turningOn: true, existingRuleID: UUID(), categoryID: UUID()), .none)
  }

  /// Turning the switch off deletes the rule this switch reads, by its id.
  func testRuleSwitchOffWithAnExistingRuleDeletesThatID() {
    let rule = UUID()
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(turningOn: false, existingRuleID: rule, categoryID: UUID()),
      .delete(rule))
  }

  /// Turning the switch off with no rule to delete writes nothing.
  func testRuleSwitchOffWithNoRuleDoesNothing() {
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(turningOn: false, existingRuleID: nil, categoryID: UUID()), .none)
  }

  /// A row with no category cannot take a rule, so turning on writes nothing.
  func testRuleSwitchOnWithoutACategoryDoesNothing() {
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(turningOn: true, existingRuleID: nil, categoryID: nil), .none)
  }

  // MARK: - S3a fix round: transfer leg predicates (Lim's M4)

  func testCategoryChipIsDisabledForATransferLeg() {
    XCTAssertFalse(TransactionDetailLogic.categoryChipEnabled(isTransfer: true))
    XCTAssertTrue(TransactionDetailLogic.categoryChipEnabled(isTransfer: false))
  }

  func testSuggestionIsNeverOfferedOnATransferLeg() {
    XCTAssertFalse(TransactionDetailLogic.suggestionAllowed(isTransfer: true))
    XCTAssertTrue(TransactionDetailLogic.suggestionAllowed(isTransfer: false))
  }

  // MARK: - S3b follow-up 1: a transfer leg's delete copy

  /// Deleting one leg of a transfer leaves the partner counting again (B9), so the
  /// alert says so, after the sentence about the totals.
  func testDeleteConfirmationAddsTheTransferSentenceForATransferLeg() {
    XCTAssertEqual(
      TransactionDetailLogic.deleteConfirmationSentence(
        amountText: "₹845.00", merchant: "Ola", date: kolkataDate(13, 21, 42), calendar: kolkata, isTransfer: true),
      "₹845.00 to Ola on 13 Nov will be removed from every total. Its matching transfer will count as an ordinary transaction."
    )
  }

  func testDeleteConfirmationOmitsTheTransferSentenceForAnOrdinaryRow() {
    XCTAssertEqual(
      TransactionDetailLogic.deleteConfirmationSentence(
        amountText: "₹845.00", merchant: "Ola", date: kolkataDate(13, 21, 42), calendar: kolkata, isTransfer: false),
      "₹845.00 to Ola on 13 Nov will be removed from every total.")
  }

  // MARK: - S3b follow-up 2: a seeded rule that already files this merchant

  func testSystemRuleCoversOnlyTheSamePatternAndCategoryAndOnlyASystemRule() {
    let food = UUID()
    let bills = UUID()
    let rules: [TransactionDetailLogic.RuleRef] = [
      .init(id: UUID(), pattern: "*OLACABS*", categoryID: food, isSystem: true),
      .init(id: UUID(), pattern: "*OLACABS*", categoryID: bills, isSystem: false),
      .init(id: UUID(), pattern: "*OLA*", categoryID: food, isSystem: true),
    ]
    XCTAssertTrue(TransactionDetailLogic.systemRuleCovers(among: rules, pattern: "*OLACABS*", categoryID: food))
    XCTAssertFalse(TransactionDetailLogic.systemRuleCovers(among: rules, pattern: "*OLACABS*", categoryID: bills))
    XCTAssertFalse(TransactionDetailLogic.systemRuleCovers(among: rules, pattern: "*OLACABS*", categoryID: UUID()))
    XCTAssertFalse(TransactionDetailLogic.systemRuleCovers(among: rules, pattern: "*UBER*", categoryID: food))
  }

  /// The seeded rule already files the row under this category: no duplicate user rule.
  func testSwitchOnWhenTheSeededRuleCoversTheCategoryCreatesNothing() {
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(
        turningOn: true, existingRuleID: nil, categoryID: UUID(), seededCovers: true),
      .none)
  }

  /// A different category is a real override, so the user rule is created.
  func testSwitchOnWhenTheSeededRuleFilesAnotherCategoryCreatesTheOverride() {
    let category = UUID()
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(
        turningOn: true, existingRuleID: nil, categoryID: category, seededCovers: false),
      .create(categoryID: category))
  }

  /// A seeded rule cannot be deleted by the switch, so turning it off writes nothing.
  func testSwitchOffWhenOnlyTheSeededRuleCoversWritesNothing() {
    XCTAssertEqual(
      TransactionDetailLogic.ruleSwitchAction(
        turningOn: false, existingRuleID: nil, categoryID: UUID(), seededCovers: true),
      .none)
  }

  /// The caption under a locked switch names the merchant the seeded rule files.
  func testSeededRuleCaptionNamesTheMerchant() {
    XCTAssertEqual(TransactionDetailLogic.seededRuleText(merchant: "Olacabs"), "Nomi already files Olacabs here")
  }

  /// The switch reads on for a seeded rule and cannot be changed: its state is
  /// the seeded rule's, not a user rule's to remove.
  func testRuleSwitchIsLockedWhenTheSeededRuleCovers() {
    XCTAssertFalse(TransactionDetailLogic.ruleSwitchEnabled(categoryID: UUID(), seededCovers: true))
    XCTAssertTrue(TransactionDetailLogic.ruleSwitchEnabled(categoryID: UUID(), seededCovers: false))
    XCTAssertFalse(TransactionDetailLogic.ruleSwitchEnabled(categoryID: nil, seededCovers: false))
  }
}
