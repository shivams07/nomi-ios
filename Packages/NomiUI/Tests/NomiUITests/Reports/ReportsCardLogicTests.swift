import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// The pure rules behind the Insights cards (S6): the bar labels, bar heights and
/// caption, the Kept figure, whole-rupee text and the merchant copy.
final class ReportsCardLogicTests: XCTestCase {
  private var india: Calendar { NomiCalendar.india }

  // MARK: - Bar labels

  /// Whole rupees under a thousand, exact.
  func testBarLabelUnderAThousandIsExact() {
    XCTAssertEqual(ReportsBarLabel.compact(minor: 999_00), "999")
    XCTAssertEqual(ReportsBarLabel.compact(minor: 0), "0")
  }

  /// Rounded thousands under a lakh.
  func testBarLabelUnderALakhIsRoundedThousands() {
    XCTAssertEqual(ReportsBarLabel.compact(minor: 41_000_00), "41k")
    XCTAssertEqual(ReportsBarLabel.compact(minor: 41_500_00), "42k", "half up")
  }

  /// Lakhs to one decimal place, half up.
  func testBarLabelFromALakhIsOneDecimalLakhs() {
    XCTAssertEqual(ReportsBarLabel.compact(minor: 1_25_000_00), "1.3L")
    XCTAssertEqual(ReportsBarLabel.compact(minor: 1_00_000_00), "1.0L")
  }

  /// 99,600 would round to "100k"; it reads as a lakh instead.
  func testBarLabelJustUnderALakhDoesNotSayOneHundredThousand() {
    XCTAssertEqual(ReportsBarLabel.compact(minor: 99_600_00), "1.0L")
  }

  // MARK: - Bar geometry

  /// A month with no spend still draws a 2 pt stub.
  func testZeroValueDrawsTheStub() {
    XCTAssertEqual(ReportsBars.barHeight(value: 0, peak: 100_00), ReportsBars.stubHeight)
    XCTAssertEqual(ReportsBars.barHeight(value: 0, peak: 0), ReportsBars.stubHeight)
  }

  func testPeakBarIsTheFullHeight() {
    XCTAssertEqual(ReportsBars.barHeight(value: 50, peak: 50), ReportsBars.maxBarHeight)
  }

  func testATinyValueNeverDropsBelowTheStub() {
    XCTAssertEqual(ReportsBars.barHeight(value: 1, peak: 1_000_000), ReportsBars.stubHeight)
  }

  // MARK: - Caption

  /// The current month's bars carry the day count; any other month has no caption.
  func testCaptionNamesTheDayOnlyForTheCurrentMonth() {
    let now = india.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9))!
    let thisMonth = india.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
    let august = india.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!

    XCTAssertEqual(
      ReportsBars.caption(anchor: thisMonth, now: now, calendar: india),
      "November is 14 days in. Tap a month to open it."
    )
    XCTAssertNil(ReportsBars.caption(anchor: august, now: now, calendar: india))
  }

  func testShortMonthUsesTheArtboardForm() {
    XCTAssertEqual(ReportsPeriod.shortMonthName(9), "Sep")
    XCTAssertEqual(ReportsPeriod.shortMonthName(1), "Jan")
  }

  // MARK: - Kept

  /// Kept is credit minus debit, and the share of income is shown with it.
  func testKeptIsPositiveWhenIncomeExceedsSpend() {
    let kept = ReportsKept.minor(creditMinor: 38_500_00, debitMinor: 35_318_00)
    XCTAssertEqual(kept, 3_182_00)
    XCTAssertEqual(ReportsKept.percentText(keptMinor: kept, creditMinor: 38_500_00), "8%")
  }

  func testKeptIsNegativeWhenSpendExceedsIncome() {
    let kept = ReportsKept.minor(creditMinor: 1_000_00, debitMinor: 1_200_00)
    XCTAssertEqual(kept, -200_00)
    XCTAssertEqual(ReportsKept.percentText(keptMinor: kept, creditMinor: 1_000_00), "\u{2212}20%")
  }

  /// No income recorded: no percentage, and the card says so.
  func testZeroIncomeHasNoShareOfIncome() {
    let kept = ReportsKept.minor(creditMinor: 0, debitMinor: 450_00)
    XCTAssertEqual(kept, -450_00)
    XCTAssertNil(ReportsKept.percentText(keptMinor: kept, creditMinor: 0))
  }

  // MARK: - Whole rupees

  func testWholeRupeesDropThePaiseWithGrouping() {
    XCTAssertEqual(ReportsRupees.whole(minor: 18_000_00), "₹18,000")
    XCTAssertEqual(ReportsRupees.whole(minor: 12_500_000), "₹1,25,000")
  }

  func testWholeRupeesRoundHalfUp() {
    XCTAssertEqual(ReportsRupees.whole(minor: 2_480_50), "₹2,481")
    XCTAssertEqual(ReportsRupees.whole(minor: 2_480_49), "₹2,480")
  }

  // MARK: - Merchants

  /// "1 payment" and "6 payments" come from the catalogue's plural variations.
  func testPaymentsLineIsPlural() {
    XCTAssertEqual(ReportsMerchantsCard.paymentsLine(count: 1), "1 payment")
    XCTAssertEqual(ReportsMerchantsCard.paymentsLine(count: 6), "6 payments")
  }
}
