import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// HM2. The Remaining budget card's wording and over-budget rule, and the
/// Needs-you line. The plan's file list has no NeedsYou test file, so the
/// Needs-you line tests sit here, in the card-copy file beside the budget card.
final class RemainingBudgetCardTests: XCTestCase {

  func testCaptionNamesWhatIsSpentAndWhatIsBudgeted() {
    XCTAssertEqual(
      RemainingBudgetText.caption(spentMinor: 6_482_400, budgetMinor: 8_000_000),
      "₹64,824.00 spent of ₹80,000.00 budgeted"
    )
  }

  func testZeroSpendStillReadsAsACaption() {
    XCTAssertEqual(
      RemainingBudgetText.caption(spentMinor: 0, budgetMinor: 8_000_000),
      "₹0.00 spent of ₹80,000.00 budgeted"
    )
  }

  /// Exactly zero left is not over. The boundary is strict.
  func testOverIsStrictlyBelowZero() {
    XCTAssertFalse(RemainingBudgetText.isOver(remainingMinor: 0))
    XCTAssertFalse(RemainingBudgetText.isOver(remainingMinor: 1))
    XCTAssertTrue(RemainingBudgetText.isOver(remainingMinor: -1))
  }

  func testUnderBudgetLabelSaysLeft() {
    let label = RemainingBudgetText.accessibilityLabel(remainingMinor: 1_517_576, budgetMinor: 8_000_000)
    XCTAssertEqual(label, "Remaining budget: ₹15,175.76 left of ₹80,000.00")
  }

  /// The over state must say "over" in words, because colour alone is not a signal.
  func testOverLabelSaysOverInWordsAndGivesTheAmountNotASign() {
    let label = RemainingBudgetText.accessibilityLabel(remainingMinor: -60_000, budgetMinor: 1_800_000)
    XCTAssertTrue(label.contains("₹600.00 over"))
    XCTAssertFalse(label.contains("−"))
    XCTAssertFalse(label.contains("-"))
  }
}

/// HM2 edges: counts 0 gives the caught-up row (no line is asked for), a
/// review count leads, and uncategorized shows only when nothing needs review.
final class NeedsYouTextTests: XCTestCase {

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
