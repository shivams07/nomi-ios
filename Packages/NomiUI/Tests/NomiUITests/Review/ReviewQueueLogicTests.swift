import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S4 step 1 and the pure rules behind the queue: the order of its rows, the month
/// filter, Home's count (S1b), the reason and caption words a row carries, and the
/// category tiles.
final class ReviewQueueLogicTests: XCTestCase {
  private let calendar = NomiCalendar.india

  /// 16 Nov 2026, the day every fixture is written against.
  private var now: Date { day(16, month: 11) }

  private func day(_ dayOfMonth: Int, month: Int, hour: Int = 12, minute: Int = 0) -> Date {
    let parts = DateComponents(
      calendar: calendar, timeZone: calendar.timeZone,
      year: 2026, month: month, day: dayOfMonth, hour: hour, minute: minute)
    return calendar.date(from: parts)!
  }

  private func row(
    _ name: String,
    on date: Date,
    categoryID: UUID? = nil,
    categorySource: CategorySource = .none,
    accountID: UUID? = UUID(),
    needsReview: Bool = false,
    reason: NeedsReviewReason? = nil,
    mergedCount: Int = 1,
    isTransfer: Bool = false,
    upiKind: String? = nil,
    source: IngestSource = .email
  ) -> NomiCore.Transaction {
    NomiCore.Transaction(
      date: date,
      descriptionText: name,
      merchantName: name,
      upiKindRaw: upiKind,
      normalizedDescription: normalizeDescription(name),
      amountMinor: 115_000,
      categoryID: categoryID,
      categorySourceRaw: categorySource.rawValue,
      accountID: accountID,
      sourceRaw: source.rawValue,
      mergedCount: mergedCount,
      needsReview: needsReview,
      needsReviewReasonRaw: reason?.rawValue,
      transferGroupID: isTransfer ? UUID() : nil,
      transferSourceRaw: isTransfer ? TransferSource.auto.rawValue : nil
    )
  }

  private func slice(_ id: UUID, _ totalMinor: Int) -> CategorySlice {
    CategorySlice(id: id, name: "Category", paletteSlot: 0, totalMinor: totalMinor, share: 0)
  }

  // MARK: - Order and membership

  func testFlaggedRowsLeadNewestFirst() {
    let older = row("Older", on: day(10, month: 11), needsReview: true, reason: .heuristic)
    let newer = row("Newer", on: day(15, month: 11), needsReview: true, reason: .heuristic)

    let items = ReviewQueueLogic.items(flagged: [older, newer], monthRows: [], now: now, calendar: calendar)

    XCTAssertEqual(items.map(\.id), [newer.id, older.id])
  }

  func testFlaggedRowsFromEarlierMonthsStayListed() {
    let october = row("October", on: day(31, month: 10), needsReview: true, reason: .heuristic)

    let items = ReviewQueueLogic.items(flagged: [october], monthRows: [], now: now, calendar: calendar)

    XCTAssertEqual(items.map(\.id), [october.id])
  }

  func testUncategorisedMonthRowsFollowTheFlaggedRowsNewestFirst() {
    let flagged = row("Flagged", on: day(1, month: 11), needsReview: true, reason: .heuristic)
    let early = row("Early", on: day(12, month: 11))
    let late = row("Late", on: day(14, month: 11))

    let items = ReviewQueueLogic.items(
      flagged: [flagged], monthRows: [early, late], now: now, calendar: calendar)

    XCTAssertEqual(items.map(\.id), [flagged.id, late.id, early.id])
  }

  func testAFlaggedRowIsListedOnceEvenWhenTheMonthAlsoHoldsIt() {
    let flagged = row("Flagged", on: day(5, month: 11), needsReview: true, reason: .heuristic)

    let items = ReviewQueueLogic.items(
      flagged: [flagged], monthRows: [flagged], now: now, calendar: calendar)

    XCTAssertEqual(items.map(\.id), [flagged.id])
  }

  func testCategorisedMonthRowsAreNotListed() {
    let categorised = row(
      "Categorised", on: day(12, month: 11), categoryID: UUID(), categorySource: .manual)

    let items = ReviewQueueLogic.items(
      flagged: [], monthRows: [categorised], now: now, calendar: calendar)

    XCTAssertTrue(items.isEmpty)
  }

  func testTransferLegsAreNotListedFromTheMonth() {
    let leg = row("Transfer to savings", on: day(12, month: 11), isTransfer: true)

    let items = ReviewQueueLogic.items(flagged: [], monthRows: [leg], now: now, calendar: calendar)

    XCTAssertTrue(items.isEmpty)
  }

  func testPreviousMonthUncategorisedRowsAreNotListed() {
    let october = row("October", on: day(31, month: 10))

    let items = ReviewQueueLogic.items(
      flagged: [], monthRows: [october], now: now, calendar: calendar)

    XCTAssertTrue(items.isEmpty)
  }

  func testAFlaggedRowThatIsAlreadyCategorisedIsStillListed() {
    let flagged = row(
      "Heuristic", on: day(13, month: 11), categoryID: UUID(), categorySource: .rule,
      needsReview: true, reason: .heuristic)

    let items = ReviewQueueLogic.items(
      flagged: [flagged], monthRows: [], now: now, calendar: calendar)

    XCTAssertEqual(items.map(\.id), [flagged.id])
  }

  func testCountIsTheNumberOfItems() {
    let flagged = [row("A", on: day(10, month: 11), needsReview: true, reason: .heuristic)]
    let month = [row("B", on: day(12, month: 11)), row("C", on: day(13, month: 11))]

    let count = ReviewQueueLogic.count(flagged: flagged, monthRows: month, now: now, calendar: calendar)

    XCTAssertEqual(count, 3)
    XCTAssertEqual(
      count,
      ReviewQueueLogic.items(flagged: flagged, monthRows: month, now: now, calendar: calendar).count)
  }

  // MARK: - Reason words

  func testAnUncategorisedRowNeedsACategory() {
    let uncategorised = row("Unsorted", on: now, needsReview: true, reason: .heuristic)

    XCTAssertEqual(ReviewQueueLogic.reasonText(for: uncategorised), "Needs a category")
  }

  func testAFlaggedCategorisedRowSaysWhyItWasFlagged() {
    let unsure = row(
      "Unsure", on: now, categoryID: UUID(), categorySource: .rule, needsReview: true, reason: .heuristic)
    let unverified = row(
      "Unverified", on: now, categoryID: UUID(), needsReview: true, reason: .unauthenticatedSender)

    XCTAssertEqual(ReviewQueueLogic.reasonText(for: unsure), "Read from an unfamiliar email")
    XCTAssertEqual(ReviewQueueLogic.reasonText(for: unverified), "Sender not verified")
  }

  func testARowWithoutAnAccountSaysSo() {
    let unassigned = row("Cash", on: now, categoryID: UUID(), accountID: nil)

    XCTAssertEqual(ReviewQueueLogic.reasonText(for: unassigned), "No account assigned")
  }

  func testAMergedRowSaysHowManySourcesItCameFrom() {
    let merged = row("Merged", on: now, categoryID: UUID(), mergedCount: 2)

    XCTAssertEqual(ReviewQueueLogic.reasonText(for: merged), "Merged from 2 sources")
  }

  func testATransferLegDoesNotNeedACategory() {
    let leg = row("Transfer", on: now, isTransfer: true)

    XCTAssertEqual(ReviewQueueLogic.reasonText(for: leg), "Needs review")
  }

  // MARK: - Source and caption

  func testAUPIRowSaysUPI() {
    let upi = row("SBI", on: now, upiKind: "p2m", source: .email)

    XCTAssertEqual(ReviewQueueLogic.sourceLabel(for: upi), "UPI")
  }

  func testOtherRowsSayWhereTheyCameFrom() {
    XCTAssertEqual(ReviewQueueLogic.sourceLabel(for: row("Bank", on: now, source: .email)), "Bank alert")
    XCTAssertEqual(ReviewQueueLogic.sourceLabel(for: row("Statement", on: now, source: .file)), "Statement")
    XCTAssertEqual(ReviewQueueLogic.sourceLabel(for: row("Typed", on: now, source: .manual)), "Added by hand")
  }

  func testCaptionNamesTheDayTimeSourceAndNoAccountWhenNoneIsMatched() {
    let alert = row("SBI Merchant Food Court", on: day(13, month: 11, hour: 13, minute: 18), upiKind: "p2m")

    let caption = ReviewQueueLogic.caption(
      for: alert, accountName: nil, now: day(14, month: 11), calendar: calendar)

    XCTAssertEqual(caption, "Yesterday, 13 Nov · 1:18 pm · UPI · no account matched")
  }

  func testCaptionNamesTheAccountWhenThereIsOne() {
    let alert = row("SBI Merchant Food Court", on: day(13, month: 11, hour: 13, minute: 18), upiKind: "p2m")

    let caption = ReviewQueueLogic.caption(
      for: alert, accountName: "HDFC ••4471", now: day(14, month: 11), calendar: calendar)

    XCTAssertEqual(caption, "Yesterday, 13 Nov · 1:18 pm · UPI · HDFC ••4471")
  }

  // MARK: - Category tiles

  func testTilesAreTheBestGuessThenTheTwoMostUsed() {
    let best = UUID()
    let first = UUID()
    let second = UUID()
    let third = UUID()

    let ids = ReviewQueueLogic.choiceIDs(
      bestGuess: best,
      history: [slice(best, 500), slice(first, 300), slice(second, 200), slice(third, 100)])

    XCTAssertEqual(ids, [best, first, second])
  }

  func testWithoutABestGuessTheTwoMostUsedLead() {
    let first = UUID()
    let second = UUID()
    let third = UUID()

    let ids = ReviewQueueLogic.choiceIDs(
      bestGuess: nil,
      history: [slice(third, 100), slice(first, 300), slice(second, 200)])

    XCTAssertEqual(ids, [first, second])
  }

  func testTheBestGuessIsNeverRepeatedByTheHistory() {
    let best = UUID()
    let other = UUID()

    let ids = ReviewQueueLogic.choiceIDs(
      bestGuess: best, history: [slice(best, 900), slice(other, 100)])

    XCTAssertEqual(ids, [best, other])
    XCTAssertEqual(Set(ids).count, ids.count)
  }

  func testTheUncategorisedAndOverflowSlicesAreNeverTiles() {
    let real = UUID()

    let ids = ReviewQueueLogic.choiceIDs(
      bestGuess: nil,
      history: [
        slice(NomiCore.Category.uncategorizedID, 900),
        slice(ReportsCategoryFold.otherOverflowID, 800),
        slice(real, 100),
      ])

    XCTAssertEqual(ids, [real])
  }

  func testFewerHistoryCategoriesGiveFewerTiles() {
    let only = UUID()

    XCTAssertEqual(ReviewQueueLogic.choiceIDs(bestGuess: nil, history: [slice(only, 10)]), [only])
    XCTAssertEqual(ReviewQueueLogic.choiceIDs(bestGuess: nil, history: []), [])
  }

  func testOnlyAOneWordLabelIsSingleWord() {
    XCTAssertTrue(ReviewQueueLogic.isSingleWord("Groceries"))
    XCTAssertFalse(ReviewQueueLogic.isSingleWord("Eating out"))
  }

  // MARK: - Stored rules

  func testAStoredRuleFilesTheMerchantOnlyUnderItsCategory() {
    let category = UUID()
    let other = UUID()
    let rule = ReviewQueueRule(pattern: "*BLUE TOKAI*", categoryID: category, isEnabled: true)

    XCTAssertTrue(
      ReviewQueueLogic.ruleFiles(
        [rule], pattern: "*BLUE TOKAI*", normalizedDescription: "UPI/BLUE TOKAI", categoryID: category))
    XCTAssertFalse(
      ReviewQueueLogic.ruleFiles(
        [rule], pattern: "*BLUE TOKAI*", normalizedDescription: "UPI/BLUE TOKAI", categoryID: other))
  }

  func testADisabledRuleFilesNothing() {
    let category = UUID()
    let rule = ReviewQueueRule(pattern: "*BLUE TOKAI*", categoryID: category, isEnabled: false)

    XCTAssertFalse(
      ReviewQueueLogic.ruleFiles(
        [rule], pattern: "*BLUE TOKAI*", normalizedDescription: "UPI/BLUE TOKAI", categoryID: category))
  }

  func testASeedGlobThatMatchesTheRowCountsAsFilingIt() {
    let category = UUID()
    let seed = ReviewQueueRule(pattern: "*OLACABS*", categoryID: category, isEnabled: true)

    XCTAssertTrue(
      ReviewQueueLogic.ruleFiles(
        [seed], pattern: "*OLA CABS*", normalizedDescription: "UPI/OLACABS/TRIP", categoryID: category))
    XCTAssertFalse(
      ReviewQueueLogic.ruleFiles(
        [seed], pattern: "*SWIGGY*", normalizedDescription: "UPI/SWIGGY", categoryID: category))
  }
}
