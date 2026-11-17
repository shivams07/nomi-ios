import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// S1b. The Left to spend card's figures: what is left, the state tag, the
/// trailing pace caption (days left and whole rupees a day), and the caption
/// under the bar. The Needs-you line tests at the end pin the copy that
/// `PluralCopyTests` also reads.
final class RemainingBudgetCardTests: XCTestCase {
  private let calendar = NomiCalendar.india

  private func day(_ dayOfMonth: Int, month: Int) -> Date {
    let parts = DateComponents(
      calendar: calendar, timeZone: calendar.timeZone,
      year: 2026, month: month, day: dayOfMonth, hour: 12)
    return calendar.date(from: parts)!
  }

  // MARK: - Caption

  func testCaptionNamesSpentBudgetedAndCategories() {
    XCTAssertEqual(
      RemainingBudgetText.caption(spentMinor: 1_227_900, budgetMinor: 1_360_000, categoryCount: 4),
      "₹12,279.00 spent of ₹13,600.00 budgeted across 4 categories"
    )
  }

  func testCaptionCountsOneCategoryInTheSingular() {
    XCTAssertEqual(
      RemainingBudgetText.caption(spentMinor: 0, budgetMinor: 800_000, categoryCount: 1),
      "₹0.00 spent of ₹8,000.00 budgeted across 1 category"
    )
  }

  // MARK: - Left and over

  /// The amount is `max(0, budget − spent)`: money left, never negative.
  func testLeftIsBudgetMinusSpent() {
    XCTAssertEqual(RemainingBudgetText.leftMinor(budgetMinor: 1_360_000, spentMinor: 1_227_900), 132_100)
  }

  func testLeftIsZeroWhenOverBudget() {
    XCTAssertEqual(RemainingBudgetText.leftMinor(budgetMinor: 1_800_000, spentMinor: 1_860_000), 0)
  }

  /// Exactly zero left is not over. The boundary is strict.
  func testOverIsStrictlyBelowZero() {
    XCTAssertFalse(RemainingBudgetText.isOver(remainingMinor: 0))
    XCTAssertFalse(RemainingBudgetText.isOver(remainingMinor: 1))
    XCTAssertTrue(RemainingBudgetText.isOver(remainingMinor: -1))
  }

  // MARK: - State tag

  func testNoTagWellUnderNinetyPercent() {
    XCTAssertNil(RemainingBudgetText.tag(spentMinor: 800_000, budgetMinor: 1_000_000))
  }

  /// Close is the 90% line, inclusive. 12,279 of 13,600 is 90% of the budget used.
  func testCloseTagReadsPercentOfBudgetUsedInWarningTone() {
    let tag = RemainingBudgetText.tag(spentMinor: 1_227_900, budgetMinor: 1_360_000)
    XCTAssertEqual(tag?.text, "90% of budget used")
    XCTAssertEqual(tag?.tone, .warning)
  }

  func testOverTagSaysOverBudgetInErrorTone() {
    let tag = RemainingBudgetText.tag(spentMinor: 1_860_000, budgetMinor: 1_800_000)
    XCTAssertEqual(tag?.text, "Over budget")
    XCTAssertEqual(tag?.tone, .error)
  }

  /// Spending exactly the budget is over, not close.
  func testExactlyTheBudgetIsOver() {
    XCTAssertEqual(RemainingBudgetText.tag(spentMinor: 1_000_000, budgetMinor: 1_000_000)?.text, "Over budget")
  }

  // MARK: - Pace caption

  /// 14 Nov in a 30-day month is 17 days, inclusive. 1,321 left over 17 days is
  /// floor(132100 / 17) = 7770 paise, which is ₹77 a day. The canvas's ₹78 rounds;
  /// the app floors (Corrections 10).
  func testPaceCaptionFourteenNovemberInThirtyDayMonthIsSeventeenDaysAtFloorRupees() {
    XCTAssertEqual(
      RemainingBudgetCard.paceCaption(
        leftMinor: 132_100, today: day(14, month: 11), periodEnd: day(30, month: 11), calendar: calendar),
      "17 days left · ₹77 a day"
    )
  }

  func testPaceCaptionReadsZeroADayWhenOver() {
    XCTAssertEqual(
      RemainingBudgetCard.paceCaption(
        leftMinor: 0, today: day(14, month: 11), periodEnd: day(30, month: 11), calendar: calendar),
      "17 days left · ₹0 a day"
    )
  }

  /// On the last day of the period, one day is left.
  func testPaceCaptionOnTheLastDayCountsOneDay() {
    XCTAssertEqual(
      RemainingBudgetCard.paceCaption(
        leftMinor: 132_100, today: day(30, month: 11), periodEnd: day(30, month: 11), calendar: calendar),
      "1 day left · ₹1,321 a day"
    )
  }

  /// A viewed month that has already ended has no pace. The caption is omitted,
  /// not shown as "0 days left".
  func testPaceCaptionIsNilAfterThePeriodEnded() {
    XCTAssertNil(
      RemainingBudgetCard.paceCaption(
        leftMinor: 132_100, today: day(14, month: 11), periodEnd: day(31, month: 10), calendar: calendar)
    )
  }

  func testPeriodEndIsTheLastDayOfTheAnchorMonth() {
    XCTAssertEqual(
      RemainingBudgetCard.periodEnd(for: day(14, month: 11), calendar: calendar),
      day(30, month: 11)
    )
  }

  // MARK: - Needs-you line (PluralCopyTests reads these)

  func testReviewCountLeadsWithPluralNoun() {
    XCTAssertEqual(NeedsYouText.line(needsReviewCount: 2, uncategorizedCount: 0), "2 transactions to review")
  }

  func testSingleReviewUsesSingularNoun() {
    XCTAssertEqual(NeedsYouText.line(needsReviewCount: 1, uncategorizedCount: 0), "1 transaction to review")
  }

  func testUncategorizedShowsOnlyWhenNothingNeedsReview() {
    XCTAssertEqual(NeedsYouText.line(needsReviewCount: 0, uncategorizedCount: 3), "3 uncategorized transactions")
    XCTAssertEqual(NeedsYouText.line(needsReviewCount: 0, uncategorizedCount: 1), "1 uncategorized transaction")
  }

  func testReviewCountWinsWhenBothArePositive() {
    XCTAssertEqual(NeedsYouText.line(needsReviewCount: 2, uncategorizedCount: 5), "2 transactions to review")
  }
}
