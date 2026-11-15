// clt-harness: include
import Foundation
import NomiCore
import Testing
@testable import NomiUI

/// NomiComparisonCopy (F2a, I-17). The copy under a Home or Insights total
/// that compares it with the earlier period.
@Suite("Comparison copy")
struct NomiComparisonCopyTests {
  private static let kolkata: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }()

  // MARK: - Line

  @Test func noPriorPeriodGivesNoLine() {
    #expect(NomiComparisonCopy.line(kind: .spent, currentMinor: 100, priorMinor: nil, priorLabel: "October") == nil)
  }

  @Test func zeroPriorSaysNothingToCompare() {
    #expect(
      NomiComparisonCopy.line(kind: .spent, currentMinor: 35_318_00, priorMinor: 0, priorLabel: "October")
        == "Nothing spent in October to compare"
    )
    #expect(
      NomiComparisonCopy.line(kind: .income, currentMinor: 35_318_00, priorMinor: 0, priorLabel: "October")
        == "Nothing received in October to compare"
    )
  }

  @Test func equalAmountsSayTheSame() {
    #expect(
      NomiComparisonCopy.line(kind: .spent, currentMinor: 50_173_00, priorMinor: 50_173_00, priorLabel: "October")
        == "Same as October"
    )
  }

  @Test func wholeRupeeDifferenceDropsTheDecimals() {
    #expect(
      NomiComparisonCopy.line(kind: .spent, currentMinor: 35_318_00, priorMinor: 50_173_00, priorLabel: "October")
        == "₹14,855 less than October"
    )
  }

  @Test func paiseDifferenceKeepsTwoDecimals() {
    #expect(
      NomiComparisonCopy.line(kind: .spent, currentMinor: 3_00, priorMinor: 1_50, priorLabel: "October")
        == "₹1.50 more than October"
    )
  }

  @Test func higherCurrentSaysMore() {
    #expect(
      NomiComparisonCopy.line(kind: .income, currentMinor: 60_000_00, priorMinor: 50_000_00, priorLabel: "last year")
        == "₹10,000 more than last year"
    )
  }

  @Test func negativeInputGivesNoLine() {
    #expect(NomiComparisonCopy.line(kind: .spent, currentMinor: -1, priorMinor: 100, priorLabel: "October") == nil)
    #expect(NomiComparisonCopy.line(kind: .spent, currentMinor: 100, priorMinor: -1, priorLabel: "October") == nil)
  }

  // MARK: - Prior label

  @Test func financialYearIsLastYearEitherWay() {
    let period = InsightPeriod.financialYear(startingYear: 2026)
    #expect(NomiComparisonCopy.priorLabel(period: period, short: false, calendar: Self.kolkata) == "last year")
    #expect(NomiComparisonCopy.priorLabel(period: period, short: true, calendar: Self.kolkata) == "last year")
  }

  @Test func fullMonthNameForThePriorMonth() {
    let period = InsightPeriod.month(year: 2026, month: 11)
    #expect(NomiComparisonCopy.priorLabel(period: period, short: false, calendar: Self.kolkata) == "October")
  }

  @Test func shortSeptemberInIndiaIsSept() {
    let period = InsightPeriod.month(year: 2026, month: 10)
    #expect(NomiComparisonCopy.priorLabel(period: period, short: true, calendar: Self.kolkata) == "Sept")
    #expect(NomiComparisonCopy.priorLabel(period: period, short: false, calendar: Self.kolkata) == "September")
  }

  @Test func januaryComparesWithDecember() {
    let period = InsightPeriod.month(year: 2026, month: 1)
    #expect(NomiComparisonCopy.priorLabel(period: period, short: false, calendar: Self.kolkata) == "December")
  }
}
