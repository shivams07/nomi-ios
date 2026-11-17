import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S1a. The hero's label and its comparison chip. The chip's words come from
/// `NomiComparisonCopy` (F2a), so these tests check the chip delegates to it
/// and pin only what the hero adds: which figure, which direction, and when
/// there is nothing to state.
final class HeroTotalCardTests: XCTestCase {
  private func insights(
    debit: Int,
    credit: Int = 0,
    priorDebit: Int?,
    priorCredit: Int? = nil,
    period: InsightPeriod = .month(year: 2026, month: 11)
  ) -> PeriodInsights {
    PeriodInsights(
      period: period,
      debitMinor: debit,
      creditMinor: credit,
      netMinor: credit - debit,
      priorDebitMinor: priorDebit,
      priorCreditMinor: priorCredit,
      transactionCount: 0,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )
  }

  // MARK: - Label per kind and basis

  func testLabelNamesTheKindAndTheMonth() {
    XCTAssertEqual(HeroTotalCard.label(kind: .spent, period: .month(year: 2026, month: 11)), "Spent this month")
    XCTAssertEqual(HeroTotalCard.label(kind: .income, period: .month(year: 2026, month: 11)), "Received this month")
  }

  func testLabelSaysThisYearForAFinancialYear() {
    XCTAssertEqual(HeroTotalCard.label(kind: .spent, period: .financialYear(startingYear: 2026)), "Spent this year")
    XCTAssertEqual(HeroTotalCard.label(kind: .income, period: .financialYear(startingYear: 2026)), "Received this year")
  }

  func testLabelFallsBackToThisPeriodForOtherPeriods() {
    XCTAssertEqual(HeroTotalCard.label(kind: .spent, period: .trailingMonths(3)), "Spent this period")
  }

  // MARK: - Chip delegates to NomiComparisonCopy

  /// The chip text is `NomiComparisonCopy.line`, unchanged. The hero does not
  /// write its own words for it.
  func testSpentChipTextIsNomiComparisonCopy() {
    let current = insights(debit: 35_318_00, priorDebit: 50_173_00)
    let chip = HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October")
    XCTAssertEqual(
      chip?.text,
      NomiComparisonCopy.line(kind: .spent, currentMinor: 35_318_00, priorMinor: 50_173_00, priorLabel: "October")
    )
    XCTAssertEqual(chip?.text, "₹14,855 less than October")
  }

  /// The artboard's chip carries a down arrow when the figure is lower.
  func testALowerFigureCarriesADownDirection() {
    let current = insights(debit: 35_318_00, priorDebit: 50_173_00)
    let chip = HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.direction, .down)
  }

  func testAHigherFigureCarriesAnUpDirection() {
    let current = insights(debit: 900_00, priorDebit: 400_00)
    let chip = HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.text, "₹500 more than October")
    XCTAssertEqual(chip?.direction, .up)
  }

  func testAnEqualFigureReadsSameAsWithNoDirection() {
    let current = insights(debit: 400_00, priorDebit: 400_00)
    let chip = HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.text, "Same as October")
    XCTAssertNil(chip?.direction)
  }

  /// An empty earlier month is not compared as if it were a figure of zero:
  /// the copy says there was nothing to compare with.
  func testAZeroPriorReadsNothingSpentToCompare() {
    let current = insights(debit: 500_00, priorDebit: 0)
    let chip = HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.text, "Nothing spent in October to compare")
    XCTAssertNil(chip?.direction)
  }

  func testAZeroIncomePriorReadsNothingReceivedToCompare() {
    let current = insights(debit: 0, credit: 1_000_00, priorDebit: 0, priorCredit: 0)
    let chip = HeroComparison.chip(kind: .income, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.text, "Nothing received in October to compare")
  }

  /// No earlier period at all: nothing to say, so no chip.
  func testNoChipWithoutAnEarlierPeriod() {
    let current = insights(debit: 500_00, priorDebit: nil)
    XCTAssertNil(HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October"))
  }

  /// FR1, kept: zero against a zero prior is the first-run Home, which draws no chip.
  func testNoChipForZeroAgainstZero() {
    let current = insights(debit: 0, priorDebit: 0)
    XCTAssertNil(HeroComparison.chip(kind: .spent, insights: current, priorLabel: "October"))
  }

  /// The Income line with no credits this month and none before has no chip either.
  func testIncomeWithNoCreditsHasNoChip() {
    let current = insights(debit: 300_00, credit: 0, priorDebit: 200_00, priorCredit: 0)
    XCTAssertNil(HeroComparison.chip(kind: .income, insights: current, priorLabel: "October"))
  }

  /// The Income line compares credits, not debits.
  func testIncomeChipComparesCredits() {
    let current = insights(debit: 100_00, credit: 900_00, priorDebit: 100_00, priorCredit: 300_00)
    let chip = HeroComparison.chip(kind: .income, insights: current, priorLabel: "October")
    XCTAssertEqual(chip?.text, "₹600 more than October")
    XCTAssertEqual(chip?.direction, .up)
  }

  // MARK: - Count-up, kept from v5

  func testReduceMotionRendersFinalValueImmediately() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: true), 42_318_00)
  }

  func testMotionEnabledStartsFromZeroForCountUp() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: false), 0)
  }

  // MARK: - S1b step 6: the chip wraps at accessibility sizes

  /// At the standard sizes the label and the chip share a row, as on the artboard.
  /// At accessibility sizes the chip goes under its label, so the chip's words
  /// wrap instead of truncating (PR 213, Lim: "↑ ₹4,804 more…").
  func testLabelRowStacksOnlyAtAccessibilitySizes() {
    XCTAssertFalse(HeroTotalCard.labelRowStacks(.large))
    XCTAssertFalse(HeroTotalCard.labelRowStacks(.xxxLarge))
    XCTAssertTrue(HeroTotalCard.labelRowStacks(.accessibility1))
    XCTAssertTrue(HeroTotalCard.labelRowStacks(.accessibility3))
  }

  // MARK: - AX3 hero controls: the segmented control and the period pill

  /// At the standard sizes the segments keep their arrows, as on the artboard.
  /// At accessibility sizes the arrows go, so "Income" has the segment to itself
  /// and no longer breaks mid-word ("Inco / me", Lim PR 232).
  func testSegmentShowsIconsOnlyAtStandardSizes() {
    XCTAssertTrue(HeroTotalCard.segmentShowsIcons(.large))
    XCTAssertTrue(HeroTotalCard.segmentShowsIcons(.xxxLarge))
    XCTAssertFalse(HeroTotalCard.segmentShowsIcons(.accessibility1))
    XCTAssertFalse(HeroTotalCard.segmentShowsIcons(.accessibility3))
  }

  /// The words and their order never change with size; only the glyphs do.
  func testSegmentOptionsKeepTitlesAndOrderAtEverySize() {
    let standard = HeroTotalCard.options(for: .large)
    XCTAssertEqual(standard.map { $0.title }, ["Spent", "Income"])
    XCTAssertEqual(standard.map { $0.value }, [.spent, .income])
    let standardImages: [String?] = standard.map { $0.systemImage }
    XCTAssertEqual(standardImages, ["arrow.down", "arrow.up"])

    let accessibility = HeroTotalCard.options(for: .accessibility3)
    XCTAssertEqual(accessibility.map { $0.title }, ["Spent", "Income"])
    XCTAssertEqual(accessibility.map { $0.value }, [.spent, .income])
    let accessibilityImages: [String?] = accessibility.map { $0.systemImage }
    XCTAssertEqual(accessibilityImages, [nil, nil])
  }

  /// The nav row stacks only at accessibility sizes. At the standard sizes the pill
  /// and the two circles share one row, as on the artboard.
  func testNavRowStacksOnlyAtAccessibilitySizes() {
    XCTAssertFalse(HeroTotalCard.navRowStacks(.large))
    XCTAssertFalse(HeroTotalCard.navRowStacks(.xxxLarge))
    XCTAssertTrue(HeroTotalCard.navRowStacks(.accessibility1))
    XCTAssertTrue(HeroTotalCard.navRowStacks(.accessibility3))
  }
}
