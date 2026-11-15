import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// I-10 consumer guard. `InsightsStore.byDay` carries days that have only
/// credits, as a bucket whose `debitMinor` is 0. The hero must not draw those
/// days as spending, must not change its spent line on them, and must not speak
/// them as the highest day. The hero's dense series is `HomeSparklineSeries`
/// (S1a). The last test is a control for Reports, which sums `debitMinor` and is
/// unaffected.
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

  private func spentLine(_ byDay: [DayBucket], today: Int) -> [Double] {
    HomeSparklineSeries.cumulative(
      byDay: byDay,
      kind: .spent,
      periodRange: november,
      today: day(today),
      calendar: calendar
    )
  }

  /// A credit-only day is not spend, so the spent line is the same with it and
  /// without it. It does not become a second spend point.
  func testACreditOnlyDayDoesNotChangeTheSpentLine() {
    let withCredit = [
      DayBucket(id: day(3), debitMinor: 10_000),
      DayBucket(id: day(5), debitMinor: 0, creditMinor: 40_000),
    ]
    let withoutCredit = [DayBucket(id: day(3), debitMinor: 10_000)]

    XCTAssertEqual(spentLine(withCredit, today: 5), [0, 0, 10_000, 10_000, 10_000])
    XCTAssertEqual(spentLine(withCredit, today: 5), spentLine(withoutCredit, today: 5))
  }

  /// The spent line's values are the running spend. A credit-only day sits
  /// between two spend days and holds the total flat, rather than adding a point
  /// that moves it.
  func testTheSpentLineHoldsItsValuesAcrossACreditOnlyDay() {
    let byDay = [
      DayBucket(id: day(1), debitMinor: 10_000),
      DayBucket(id: day(2), debitMinor: 0, creditMinor: 5_000),
      DayBucket(id: day(3), debitMinor: 25_000),
    ]

    XCTAssertEqual(spentLine(byDay, today: 3), [10_000, 10_000, 35_000])
  }

  /// A month with income and no spend says "No spending this period", as it did
  /// when no bucket existed at all.
  func testACreditOnlyPeriodSpeaksNoSpending() {
    let byDay = [DayBucket(id: day(1), debitMinor: 0, creditMinor: 40_000)]

    XCTAssertEqual(HeroSparkline.accessibilityValue(byDay: byDay), "No spending this period")
  }

  /// The spoken day is the last spend day. A later credit-only day must not
  /// become "Last spending on day N".
  func testTheSpokenDayIsTheLastSpendDayNotALaterCreditDay() {
    let byDay = [
      DayBucket(id: day(3), debitMinor: 10_000),
      DayBucket(id: day(9), debitMinor: 0, creditMinor: 40_000),
    ]

    XCTAssertEqual(
      HeroSparkline.accessibilityValue(byDay: byDay),
      "Last spending on day 3, \(NomiFormatters.amountString(minor: 10_000))")
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
