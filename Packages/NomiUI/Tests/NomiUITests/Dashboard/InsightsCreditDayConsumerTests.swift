import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// I-10 consumer guard. `InsightsStore.byDay` now carries days that have only
/// credits, as a bucket whose `debitMinor` is 0. The hero sparkline was written
/// when every bucket was a spend day, so these pin what it showed before the
/// change: the flat line, the step line's values, and the spoken value. The last
/// test is a control for Reports, which sums `debitMinor` and is unaffected.
final class InsightsCreditDayConsumerTests: XCTestCase {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func day(_ dayOfMonth: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth, hour: 12))!
  }

  private var november: Range<Date> {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
      ..< calendar.date(from: DateComponents(year: 2026, month: 12, day: 1))!
  }

  /// Before the change, one spend day was fewer than two buckets, so the hero
  /// drew a flat line. A credit-only day must not make it a step line.
  func testACreditOnlyDayDoesNotTurnAOneSpendDayMonthIntoAStepLine() {
    let byDay = [
      DayBucket(id: day(3), debitMinor: 10_000),
      DayBucket(id: day(5), debitMinor: 0, creditMinor: 40_000),
    ]

    XCTAssertEqual(HeroSparkline.points(byDay: byDay), [])
    XCTAssertTrue(HeroSparkline.samples(byDay: byDay, range: november).isEmpty)
  }

  /// The step line's values are the running spend. A credit-only day sits
  /// between two spend days and must hold the total flat, not add a point that
  /// changes it.
  func testTheStepLineHoldsItsValuesAcrossACreditOnlyDay() {
    let byDay = [
      DayBucket(id: day(1), debitMinor: 10_000),
      DayBucket(id: day(2), debitMinor: 0, creditMinor: 5_000),
      DayBucket(id: day(3), debitMinor: 25_000),
    ]

    XCTAssertEqual(HeroSparkline.points(byDay: byDay), [10_000, 35_000])
    XCTAssertEqual(
      HeroSparkline.samples(byDay: byDay, range: november),
      [
        HeroSparkline.Sample(date: november.lowerBound, total: 0),
        HeroSparkline.Sample(date: day(1), total: 10_000),
        HeroSparkline.Sample(date: day(3), total: 35_000),
        HeroSparkline.Sample(date: november.upperBound, total: 35_000),
      ])
  }

  /// A month with income and no spend says "No spending this period", as it did
  /// when no bucket existed at all.
  func testACreditOnlyPeriodSpeaksNoSpending() {
    let byDay = [DayBucket(id: day(1), debitMinor: 0, creditMinor: 40_000)]

    XCTAssertEqual(HeroSparkline.accessibilityValue(byDay: byDay), "No spending this period")
  }

  /// The spoken day is the last spend day. A later credit-only day must not
  /// become "Highest on day N".
  func testTheSpokenDayIsTheLastSpendDayNotALaterCreditDay() {
    let byDay = [
      DayBucket(id: day(3), debitMinor: 10_000),
      DayBucket(id: day(9), debitMinor: 0, creditMinor: 40_000),
    ]

    XCTAssertEqual(
      HeroSparkline.accessibilityValue(byDay: byDay),
      "Highest on day 3, \(NomiFormatters.amountString(minor: 10_000))")
  }

  /// Control, and expected to pass before and after: Reports sums `debitMinor`
  /// per day of month, so a credit-only bucket adds zero and the bars do not move.
  func testReportsDailyBarsAreUnchangedByACreditOnlyDay() {
    let byDay = [
      DayBucket(id: day(3), debitMinor: 50_000),
      DayBucket(id: day(5), debitMinor: 0, creditMinor: 30_000),
      DayBucket(id: day(9), debitMinor: 1_000, creditMinor: 2_000),
    ]

    let values = ReportsSpendSeries.dailyDebit(
      period: .month(year: 2026, month: 11), byDay: byDay, calendar: calendar)

    XCTAssertEqual(values?[2], 50_000)
    XCTAssertEqual(values?[4], 0)
    XCTAssertEqual(values?[8], 1_000)
    XCTAssertEqual(values?.reduce(0, +), 51_000)
  }
}
