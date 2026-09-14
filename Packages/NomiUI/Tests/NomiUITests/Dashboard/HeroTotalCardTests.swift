import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class HeroTotalCardTests: XCTestCase {
  func testDeltaIsNilWithNoPriorPeriod() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: nil))
  }

  /// v5: a zero prior is a real prior — the delta is the whole current
  /// figure, not `nil`.
  func testZeroPriorIsARealPriorNotNil() {
    let delta = HeroDelta.compute(current: 1000, prior: 0)
    XCTAssertEqual(delta?.deltaMinor, 1000)
    XCTAssertEqual(delta?.isIncrease, true)
  }

  func testDeltaFlagsIncreaseWhenCurrentExceedsPrior() {
    let delta = HeroDelta.compute(current: 1200, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.deltaMinor, 200)
  }

  func testDeltaFlagsDecreaseWhenCurrentIsBelowPrior() {
    let delta = HeroDelta.compute(current: 800, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, false)
    XCTAssertEqual(delta?.deltaMinor, -200)
  }

  func testDeltaEqualToPriorCountsAsIncrease() {
    let delta = HeroDelta.compute(current: 1000, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.deltaMinor, 0)
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

  private func day(_ offset: Int) -> Date {
    Date(timeIntervalSince1970: TimeInterval(offset * 86_400))
  }

  func testSparklineLastPointEqualsSumOfByDay() {
    let byDay = [
      DayBucket(id: day(0), debitMinor: 100),
      DayBucket(id: day(1), debitMinor: 250),
      DayBucket(id: day(2), debitMinor: 50),
    ]
    XCTAssertEqual(HeroSparkline.points(byDay: byDay).last, 400)
  }

  func testSparklineIsEmptyWithFewerThanTwoBuckets() {
    XCTAssertTrue(HeroSparkline.points(byDay: [DayBucket(id: day(0), debitMinor: 100)]).isEmpty)
    XCTAssertTrue(HeroSparkline.points(byDay: []).isEmpty)
  }

  func testSparklineSortsUnsortedInputByDay() {
    let byDay = [
      DayBucket(id: day(2), debitMinor: 50),
      DayBucket(id: day(0), debitMinor: 100),
      DayBucket(id: day(1), debitMinor: 250),
    ]
    XCTAssertEqual(HeroSparkline.points(byDay: byDay), [100, 350, 400])
  }
}
