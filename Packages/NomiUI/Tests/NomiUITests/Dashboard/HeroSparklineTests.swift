import CoreGraphics
import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S1a. The hero chart's dense daily series, its axis labels, its VoiceOver
/// value and its point geometry. Pure, so XCTest without a view. Every test
/// uses one fixed calendar (Asia/Kolkata) so the day arithmetic does not
/// depend on the machine's zone.
final class HeroSparklineTests: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }()

  /// Start of day, as `NomiCore`'s aggregator writes `DayBucket.id`.
  private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = dayOfMonth
    return calendar.date(from: components)!
  }

  private var february: Range<Date> {
    dateRange(for: .month(year: 2026, month: 2), calendar: calendar)
  }

  // MARK: - Dense cumulative series

  /// One value per day up to today, zero before the first spend day, and the
  /// running total held from there on. Day 1 is index 0.
  func testCumulativeHasOneValuePerDayUpToTodayAndHoldsTheRunningTotal() {
    let byDay = [
      DayBucket(id: day(2026, 2, 3), debitMinor: 100),
      DayBucket(id: day(2026, 2, 10), debitMinor: 250),
    ]
    let series = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: february, today: day(2026, 2, 10), calendar: calendar
    )
    XCTAssertEqual(series, [0, 0, 100, 100, 100, 100, 100, 100, 100, 350])
  }

  func testCumulativeIsMonotonicAcrossTheDays() {
    let byDay = [
      DayBucket(id: day(2026, 2, 9), debitMinor: 40),
      DayBucket(id: day(2026, 2, 2), debitMinor: 120),
      DayBucket(id: day(2026, 2, 5), debitMinor: 0),
    ]
    let series = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: february, today: day(2026, 2, 28), calendar: calendar
    )
    XCTAssertEqual(series.count, 28)
    XCTAssertEqual(series, series.sorted())
    XCTAssertEqual(series.last, 160)
  }

  /// A period that is still running stops at today; a finished one runs to its
  /// last day.
  func testCumulativeStopsAtTodayAndRunsToThePeriodEndAfterIt() {
    let series = HomeSparklineSeries.cumulative(
      byDay: [], kind: .spent, periodRange: february, today: day(2026, 2, 14), calendar: calendar
    )
    XCTAssertEqual(series.count, 14)
    let finished = HomeSparklineSeries.cumulative(
      byDay: [], kind: .spent, periodRange: february, today: day(2026, 3, 5), calendar: calendar
    )
    XCTAssertEqual(finished.count, 28)
  }

  func testCumulativeIsEmptyWhenTodayIsBeforeThePeriodStarts() {
    let series = HomeSparklineSeries.cumulative(
      byDay: [], kind: .spent, periodRange: february, today: day(2026, 1, 31), calendar: calendar
    )
    XCTAssertEqual(series, [])
  }

  /// B1 note: a credit-only day is income, and the spent line must not draw it.
  func testSpentLineDoesNotDrawIncomeDays() {
    let byDay = [DayBucket(id: day(2026, 2, 5), debitMinor: 0, creditMinor: 50_000)]
    let series = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: february, today: day(2026, 2, 28), calendar: calendar
    )
    XCTAssertEqual(series, Array(repeating: 0, count: 28))
  }

  func testIncomeLineSumsCreditsAndNotDebits() {
    let byDay = [DayBucket(id: day(2026, 2, 2), debitMinor: 30_000, creditMinor: 50_000)]
    let income = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .income, periodRange: february, today: day(2026, 2, 28), calendar: calendar
    )
    let spent = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: february, today: day(2026, 2, 28), calendar: calendar
    )
    XCTAssertEqual(income.last, 50_000)
    XCTAssertEqual(spent.last, 30_000)
  }

  /// A bucket outside the period (a stale or shifted id) adds nothing.
  func testBucketsOutsideThePeriodAreIgnored() {
    let byDay = [DayBucket(id: day(2026, 3, 2), debitMinor: 900)]
    let series = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: february, today: day(2026, 2, 28), calendar: calendar
    )
    XCTAssertEqual(series.last, 0)
  }

  // MARK: - Prior window alignment

  /// The prior line is index-aligned: index 0 is the first day of the prior
  /// window, whatever its length.
  func testPriorSeriesIsAlignedByDayIndex() {
    let january = dateRange(for: .month(year: 2026, month: 1), calendar: calendar)
    let byDay = [DayBucket(id: day(2026, 1, 1), debitMinor: 100)]
    let prior = HomeSparklineSeries.cumulative(
      byDay: byDay, kind: .spent, periodRange: january, today: january.upperBound, calendar: calendar
    )
    XCTAssertEqual(prior.count, 31)
    XCTAssertEqual(prior.first, 100)
    XCTAssertEqual(prior.last, 100)
  }

  /// A longer prior window is cut to the current period's length. A shorter
  /// one (February before a 31-day month) holds its final total to the end.
  func testAlignedTruncatesALongerPriorAndHoldsAShorterOne() {
    XCTAssertEqual(HomeSparklineSeries.aligned([1, 2, 3, 4], count: 2), [1, 2])
    XCTAssertEqual(HomeSparklineSeries.aligned([1, 2], count: 4), [1, 2, 2, 2])
    XCTAssertEqual(HomeSparklineSeries.aligned([1, 2], count: 2), [1, 2])
    XCTAssertEqual(HomeSparklineSeries.aligned([], count: 3), [])
  }

  func testDayCountIsTheNumberOfCalendarDays() {
    XCTAssertEqual(HomeSparklineSeries.dayCount(in: february, calendar: calendar), 28)
    let leap = dateRange(for: .month(year: 2024, month: 2), calendar: calendar)
    XCTAssertEqual(HomeSparklineSeries.dayCount(in: leap, calendar: calendar), 29)
  }

  // MARK: - Axis labels

  /// The artboard reads "1 Nov" and "30 Nov", so a month tick names its month.
  func testMonthTicksNameTheDayAndTheMonth() {
    let ticks = HeroSparkline.tickLabels(for: .month(year: 2026, month: 2), calendar: calendar)
    XCTAssertEqual(ticks.first, "1 Feb")
    XCTAssertEqual(ticks.last, "28 Feb")
  }

  func testLastMonthTickFollowsLeapFebruary() {
    XCTAssertEqual(HeroSparkline.tickLabels(for: .month(year: 2024, month: 2), calendar: calendar).last, "29 Feb")
  }

  func testFinancialYearTicksNameTheMonth() {
    let fy = HeroSparkline.tickLabels(for: .financialYear(startingYear: 2026), calendar: calendar)
    XCTAssertEqual(fy.first, "1 Apr")
    XCTAssertEqual(fy.last, "31 Mar")
  }

  // MARK: - VoiceOver value and the no-spend copy

  func testAccessibilityValueNamesTheLastSpendDayAndTheTotal() {
    let byDay = [
      DayBucket(id: day(2026, 2, 3), debitMinor: 100),
      DayBucket(id: day(2026, 2, 10), debitMinor: 250),
    ]
    XCTAssertEqual(
      HeroSparkline.accessibilityValue(byDay: byDay, kind: .spent, calendar: calendar),
      "Highest on day 10, ₹3.50"
    )
  }

  /// B1 note: an income-only month reads "No spending this period" on the
  /// spent line, and the income day is not counted as spending.
  func testAnIncomeOnlyMonthReadsNoSpending() {
    let byDay = [DayBucket(id: day(2026, 2, 5), debitMinor: 0, creditMinor: 500_00)]
    XCTAssertEqual(
      HeroSparkline.accessibilityValue(byDay: byDay, kind: .spent, calendar: calendar),
      "No spending this period"
    )
  }

  func testTheIncomeLineReadsNoIncomeWhenThereIsNone() {
    let byDay = [DayBucket(id: day(2026, 2, 5), debitMinor: 300_00, creditMinor: 0)]
    XCTAssertEqual(
      HeroSparkline.accessibilityValue(byDay: byDay, kind: .income, calendar: calendar),
      "No income this period"
    )
  }

  // MARK: - Geometry

  private let size = CGSize(width: 300, height: 150)

  func testTheFirstAndLastDayAreOnTheEdges() {
    let first = HomeSparklinePlot.point(index: 0, value: 0, span: 28, maxValue: 100, size: size)
    let last = HomeSparklinePlot.point(index: 27, value: 0, span: 28, maxValue: 100, size: size)
    XCTAssertEqual(first.x, 0, accuracy: 0.001)
    XCTAssertEqual(last.x, 300, accuracy: 0.001)
  }

  /// Zero sits on the baseline, and the largest value sits at the top inset,
  /// so the tooltip above the largest point has room.
  func testZeroSitsOnTheBaselineAndTheMaximumAtTheTopInset() {
    let baseline = HomeSparklinePlot.point(index: 3, value: 0, span: 28, maxValue: 100, size: size)
    let top = HomeSparklinePlot.point(index: 3, value: 100, span: 28, maxValue: 100, size: size)
    XCTAssertEqual(baseline.y, 148, accuracy: 0.001)
    XCTAssertEqual(top.y, HomeSparklinePlot.topInset, accuracy: 0.001)
  }
}
