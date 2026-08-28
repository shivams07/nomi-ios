import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class ReportsViewModelTests: XCTestCase {
  private func insights(
    period: InsightPeriod,
    debitMinor: Int,
    creditMinor: Int,
    priorDebitMinor: Int? = nil,
    priorCreditMinor: Int? = nil,
    byCategory: [CategorySlice] = []
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
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )
  }

  /// The AC's own wording: "switching basis recomputes every figure on
  /// screen (asserted by comparing two rendered view models, not by eye)."
  /// Two view models built from genuinely different period data must not be
  /// equal — proving the screen doesn't silently keep rendering the
  /// previous basis's figures.
  func testSwitchingBasisProducesADifferentViewModel() {
    let monthInsights = insights(period: .month(year: 2026, month: 8), debitMinor: 10_000_00, creditMinor: 60_000_00)
    let fyInsights = insights(period: .financialYear(startingYear: 2025), debitMinor: 120_000_00, creditMinor: 720_000_00)

    let monthModel = ReportsViewModelBuilder.make(period: .month(year: 2026, month: 8), insights: monthInsights, trend: [])
    let fyModel = ReportsViewModelBuilder.make(period: .financialYear(startingYear: 2025), insights: fyInsights, trend: [])

    XCTAssertNotEqual(monthModel, fyModel)
    XCTAssertEqual(monthModel.debitMinor, 10_000_00)
    XCTAssertEqual(fyModel.debitMinor, 120_000_00)
  }

  func testViewModelCarriesTrendUnchanged() {
    let trend = [MonthBucket(id: Date(timeIntervalSince1970: 0), debitMinor: 100, creditMinor: 200)]
    let model = ReportsViewModelBuilder.make(period: .allTime, insights: insights(period: .allTime, debitMinor: 0, creditMinor: 0), trend: trend)
    XCTAssertEqual(model.trend.map(\.id), trend.map(\.id))
  }

  func testViewModelFoldsCategoriesToSevenSlots() {
    let slices = (0..<9).map { CategorySlice(id: UUID(), name: "C\($0)", paletteSlot: $0 % 7, totalMinor: (9 - $0) * 100, share: 0.1) }
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 8),
      insights: insights(period: .month(year: 2026, month: 8), debitMinor: 100, creditMinor: 0, byCategory: slices),
      trend: []
    )
    XCTAssertEqual(model.categories.count, 8)
    XCTAssertEqual(model.categories.last?.name, "Other")
  }

  func testViewModelComputesBothDebitAndCreditDeltas() {
    let model = ReportsViewModelBuilder.make(
      period: .month(year: 2026, month: 8),
      insights: insights(period: .month(year: 2026, month: 8), debitMinor: 1200, creditMinor: 800, priorDebitMinor: 1000, priorCreditMinor: 1000),
      trend: []
    )
    XCTAssertEqual(model.debitDelta?.isIncrease, true)
    XCTAssertEqual(model.creditDelta?.isIncrease, false)
  }

  func testViewModelHasNoDeltaWhenNoPriorPeriod() {
    let model = ReportsViewModelBuilder.make(
      period: .allTime,
      insights: insights(period: .allTime, debitMinor: 100, creditMinor: 100),
      trend: []
    )
    XCTAssertNil(model.debitDelta)
    XCTAssertNil(model.creditDelta)
  }
}
