import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class HeroTotalCardTests: XCTestCase {
  func testDeltaIsNilWithNoPriorPeriod() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: nil))
  }

  /// D27: a whole-rupee delta drops ".00", as the Insights chip does.
  func testChipCopyDropsWholeRupeeDecimals() {
    let result = HeroDelta.Result(deltaMinor: 1_485_500, isIncrease: false)
    XCTAssertEqual(HeroDelta.chipCopy(result), "down ₹14,855 vs last period")
  }

  /// D27: a delta with paise keeps its decimals.
  func testChipCopyKeepsPaise() {
    let result = HeroDelta.Result(deltaMinor: 1_485_550, isIncrease: false)
    XCTAssertEqual(HeroDelta.chipCopy(result), "down ₹14,855.50 vs last period")
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

  // MARK: - HM1: the date axis, the flat zero state, the VoiceOver value, the
  // ticks and the chip copy. Pure helpers, so XCTest here (V3) and not a
  // harness file: `HeroSparkline` imports Charts.

  private func calendarDay(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = dayOfMonth
    components.hour = 12
    return Calendar.current.date(from: components)!
  }

  func testSamplesStepFromZeroAndHoldTheTotalToThePeriodEnd() {
    let range = dateRange(for: .month(year: 2026, month: 2), calendar: .current)
    let byDay = [
      DayBucket(id: calendarDay(2026, 2, 10), debitMinor: 250),
      DayBucket(id: calendarDay(2026, 2, 3), debitMinor: 100),
    ]
    let samples = HeroSparkline.samples(byDay: byDay, range: range)
    XCTAssertEqual(samples.count, 4)
    XCTAssertEqual(samples.first, HeroSparkline.Sample(date: range.lowerBound, total: 0))
    XCTAssertEqual(samples[1].total, 100)
    XCTAssertEqual(samples[2].total, 350)
    XCTAssertEqual(samples.last, HeroSparkline.Sample(date: range.upperBound, total: 350))
  }

  func testSamplesAreEmptyWithFewerThanTwoSpendDaysSoTheFlatLineDraws() {
    let range = dateRange(for: .month(year: 2026, month: 2), calendar: .current)
    XCTAssertTrue(HeroSparkline.samples(byDay: [], range: range).isEmpty)
    XCTAssertTrue(
      HeroSparkline.samples(byDay: [DayBucket(id: calendarDay(2026, 2, 3), debitMinor: 100)], range: range).isEmpty
    )
  }

  func testAccessibilityValueNamesTheLastSpendDayAndTheTotal() {
    let byDay = [
      DayBucket(id: calendarDay(2026, 2, 3), debitMinor: 100),
      DayBucket(id: calendarDay(2026, 2, 10), debitMinor: 250),
    ]
    XCTAssertEqual(HeroSparkline.accessibilityValue(byDay: byDay), "Highest on day 10, ₹3.50")
    XCTAssertEqual(HeroSparkline.accessibilityValue(byDay: []), "No spending this period")
  }

  func testMonthTicksAreDayNumbersAndFollowLeapFebruary() {
    let february2026 = HeroSparkline.tickLabels(for: .month(year: 2026, month: 2))
    XCTAssertEqual(february2026.first, "1")
    XCTAssertEqual(february2026.last, "28")
    XCTAssertEqual(HeroSparkline.tickLabels(for: .month(year: 2024, month: 2)).last, "29")
  }

  func testFinancialYearTicksNameTheMonth() {
    let fy = HeroSparkline.tickLabels(for: .financialYear(startingYear: 2026))
    XCTAssertEqual(fy.first, "1 Apr")
    XCTAssertEqual(fy.last, "31 Mar")
  }

  // MARK: - FR1: when the chip is shown at all. Zero against zero is the
  // first-run Home (no transactions, no prior period) and must draw no chip.
  // A zero delta has no direction, so it never prints "up ₹0.00".

  func testChipHiddenWhenZeroAgainstZeroPrior() {
    XCTAssertNil(HeroDelta.visibleDelta(current: 0, prior: 0))
  }

  func testChipHiddenWhenThereIsNoPriorPeriod() {
    XCTAssertNil(HeroDelta.visibleDelta(current: 0, prior: nil))
    XCTAssertNil(HeroDelta.visibleDelta(current: 500_00, prior: nil))
  }

  func testChipShownAsUpWhenPriorIsZeroAndCurrentIsNonZero() {
    let delta = HeroDelta.visibleDelta(current: 500_00, prior: 0)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.deltaMinor, 500_00)
    XCTAssertEqual(HeroDelta.chipCopy(delta!), "up ₹500 vs last period")
  }

  func testChipShownAsDownWhenCurrentIsZeroAndPriorIsNonZero() {
    let delta = HeroDelta.visibleDelta(current: 0, prior: 500_00)
    XCTAssertEqual(delta?.isIncrease, false)
    XCTAssertEqual(delta?.deltaMinor, -500_00)
    XCTAssertEqual(HeroDelta.chipCopy(delta!), "down ₹500 vs last period")
  }

  func testChipShownForNonZeroAgainstNonZeroDifferentFigures() {
    let up = HeroDelta.visibleDelta(current: 1_200_00, prior: 1_000_00)
    XCTAssertEqual(HeroDelta.chipCopy(up!), "up ₹200 vs last period")
    let down = HeroDelta.visibleDelta(current: 800_00, prior: 1_000_00)
    XCTAssertEqual(HeroDelta.chipCopy(down!), "down ₹200 vs last period")
  }

  func testChipHiddenWhenDeltaIsExactlyZeroWithData() {
    XCTAssertNil(HeroDelta.visibleDelta(current: 1_000_00, prior: 1_000_00))
  }

  /// Rounding: amounts are integer minor units and the delta is exact, so a
  /// one-paisa difference is a real change. It must show, and must not be
  /// rounded to the zero case that hides the chip.
  func testOnePaisaDeltaIsShownNotRoundedAway() {
    let up = HeroDelta.visibleDelta(current: 1, prior: 0)
    XCTAssertEqual(up?.deltaMinor, 1)
    XCTAssertEqual(HeroDelta.chipCopy(up!), "up ₹0.01 vs last period")
    let down = HeroDelta.visibleDelta(current: 100, prior: 101)
    XCTAssertEqual(down?.isIncrease, false)
    XCTAssertEqual(HeroDelta.chipCopy(down!), "down ₹0.01 vs last period")
  }

  func testChipCopyReadsTheDirectionAsAWord() {
    let up = HeroDelta.compute(current: 64_824_24, prior: 58_404_00)!
    XCTAssertEqual(HeroDelta.chipCopy(up), "up ₹6,420.24 vs last period")
    let down = HeroDelta.compute(current: 1_000_00, prior: 1_500_00)!
    XCTAssertEqual(HeroDelta.chipCopy(down), "down ₹500 vs last period")
  }
}
