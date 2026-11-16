import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class ReportsViewModelTests: XCTestCase {
  private var india: Calendar { NomiCalendar.india }

  private func insights(
    period: InsightPeriod,
    debitMinor: Int,
    creditMinor: Int,
    priorDebitMinor: Int? = nil,
    priorCreditMinor: Int? = nil,
    byCategory: [CategorySlice] = [],
    topMerchants: [MerchantTotal] = [],
    uncategorizedCount: Int = 0
  ) -> PeriodInsights {
    PeriodInsights(
      period: period,
      debitMinor: debitMinor,
      creditMinor: creditMinor,
      netMinor: creditMinor - debitMinor,
      priorDebitMinor: priorDebitMinor,
      priorCreditMinor: priorCreditMinor,
      transactionCount: byCategory.count,
      byDay: [],
      byCategory: byCategory,
      topMerchants: topMerchants,
      needsReviewCount: 0,
      uncategorizedCount: uncategorizedCount
    )
  }

  /// The R12b wording: switching basis recomputes every figure on screen.
  /// Two view models from different period data must not be equal.
  func testSwitchingBasisProducesADifferentViewModel() {
    let month = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 8),
      insights: insights(period: .month(year: 2026, month: 8), debitMinor: 10_000_00, creditMinor: 60_000_00),
      calendar: india
    )
    let year = ReportsViewModelBuilder.make(
      period: .financialYear(startingYear: 2025),
      insights: insights(period: .financialYear(startingYear: 2025), debitMinor: 120_000_00, creditMinor: 720_000_00),
      calendar: india
    )

    XCTAssertNotEqual(month, year)
    XCTAssertEqual(month.debitMinor, 10_000_00)
    XCTAssertEqual(year.debitMinor, 120_000_00)
  }

  /// The artboard's tag: the prior month's short name, the difference in whole rupees.
  func testComparisonLineNamesThePriorMonthShort() {
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 11),
      insights: insights(
        period: .month(year: 2026, month: 11),
        debitMinor: 35_318_00,
        creditMinor: 38_500_00,
        priorDebitMinor: 50_173_00,
        priorCreditMinor: 39_500_00
      ),
      calendar: india
    )

    XCTAssertEqual(model.debitComparison, "₹14,855 less than Oct")
    XCTAssertEqual(model.creditComparison, "₹1,000 less than Oct")
  }

  /// The empty-prior copy: the prior period had nothing, so the line says so.
  func testEmptyPriorSaysNothingWasSpentToCompare() {
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 11),
      insights: insights(
        period: .month(year: 2026, month: 11),
        debitMinor: 450_00,
        creditMinor: 0,
        priorDebitMinor: 0,
        priorCreditMinor: 0
      ),
      calendar: india
    )

    XCTAssertEqual(model.debitComparison, "Nothing spent in Oct to compare")
    XCTAssertEqual(model.creditComparison, "Nothing received in Oct to compare")
  }

  /// No prior period at all (not a zero one): no tag.
  func testNoPriorPeriodGivesNoComparison() {
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 11),
      insights: insights(period: .month(year: 2026, month: 11), debitMinor: 100_00, creditMinor: 100_00),
      calendar: india
    )

    XCTAssertNil(model.debitComparison)
    XCTAssertNil(model.creditComparison)
  }

  /// The financial-year basis names the earlier period "last year".
  func testFinancialYearComparesWithLastYear() {
    let model = ReportsViewModelBuilder.make(
      period: .financialYear(startingYear: 2026),
      insights: insights(
        period: .financialYear(startingYear: 2026),
        debitMinor: 600_000_00,
        creditMinor: 0,
        priorDebitMinor: 500_000_00
      ),
      calendar: india
    )

    XCTAssertEqual(model.debitComparison, "₹1,00,000 more than last year")
  }

  func testCategoriesCarryTheBreakdownAndTheUncategorisedCount() {
    let food = CategorySlice(id: UUID(), name: "Food", paletteSlot: 0, totalMinor: 300_00, share: 0.6)
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 8),
      insights: insights(
        period: .month(year: 2026, month: 8),
        debitMinor: 500_00,
        creditMinor: 0,
        byCategory: [
          food,
          CategorySlice(id: NomiCore.Category.uncategorizedID, name: "Uncategorized", paletteSlot: 0, totalMinor: 200_00, share: 0.4),
        ],
        uncategorizedCount: 3
      ),
      calendar: india
    )

    XCTAssertEqual(model.categories.rows.map(\.kind), [.category(rank: 0), .uncategorised])
    XCTAssertEqual(model.categories.totalMinor, 500_00)
    XCTAssertEqual(model.uncategorizedCount, 3)
  }

  func testTopMerchantsAndTheirCountsAreCarried() {
    let merchants = [MerchantTotal(id: "SWIGGY", label: "Swiggy", totalMinor: 5420_00, count: 6)]
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 8),
      insights: insights(period: .month(year: 2026, month: 8), debitMinor: 5420_00, creditMinor: 0, topMerchants: merchants),
      calendar: india
    )

    XCTAssertEqual(model.topMerchants.map(\.id), ["SWIGGY"])
    XCTAssertEqual(model.topMerchants.map(\.count), [6])
  }
}
