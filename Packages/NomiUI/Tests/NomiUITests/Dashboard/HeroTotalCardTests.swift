import Foundation
import XCTest
@testable import NomiUI

final class HeroTotalCardTests: XCTestCase {
  func testDeltaIsNilWithNoPriorPeriod() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: nil))
  }

  func testDeltaIsNilWhenPriorIsZero() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: 0))
  }

  func testDeltaFlagsIncreaseWhenCurrentExceedsPrior() {
    let delta = HeroDelta.compute(current: 1200, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.percent ?? 0, 0.2, accuracy: 0.0001)
  }

  func testDeltaFlagsDecreaseWhenCurrentIsBelowPrior() {
    let delta = HeroDelta.compute(current: 800, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, false)
    XCTAssertEqual(delta?.percent ?? 0, -0.2, accuracy: 0.0001)
  }

  func testDeltaEqualToPriorCountsAsIncrease() {
    let delta = HeroDelta.compute(current: 1000, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.percent ?? -1, 0, accuracy: 0.0001)
  }

  func testPercentTextRoundsToWholeNumber() {
    XCTAssertEqual(HeroDelta.percentText(0.2), "20%")
    XCTAssertEqual(HeroDelta.percentText(-0.2), "20%")
    XCTAssertEqual(HeroDelta.percentText(0.005), "1%")
  }

  func testReduceMotionRendersFinalValueImmediately() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: true), 42_318_00)
  }

  func testMotionEnabledStartsFromZeroForCountUp() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: false), 0)
  }

  func testTilesRenderBothIncomeAndExpenseFiguresFromPeriodInsights() {
    let insights = PeriodInsights(
      period: .month(year: 2026, month: 8),
      debitMinor: 42_318_00,
      creditMinor: 60_000_00,
      netMinor: 17_682_00,
      priorDebitMinor: 38_000_00,
      priorCreditMinor: 55_000_00,
      transactionCount: 74,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )

    let tiles = HeroIncomeExpense.tiles(for: insights)

    XCTAssertEqual(tiles.count, 2)
    XCTAssertEqual(
      tiles.first { $0.title == "Income" }?.amountText,
      NomiFormatters.amountString(minor: 60_000_00)
    )
    XCTAssertEqual(
      tiles.first { $0.title == "Expenses" }?.amountText,
      NomiFormatters.amountString(minor: 42_318_00)
    )
  }
}
