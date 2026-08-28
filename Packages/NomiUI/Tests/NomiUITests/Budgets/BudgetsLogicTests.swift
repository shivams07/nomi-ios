import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class BudgetsLogicTests: XCTestCase {
  func testCurrentPeriodReadsYearAndMonthFromDate() {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 15
    let calendar = Calendar(identifier: .gregorian)
    let date = calendar.date(from: components)!
    let period = BudgetPeriod.current(from: date, calendar: calendar)
    XCTAssertEqual(period.year, 2026)
    XCTAssertEqual(period.month, 8)
  }

  private func progress(fraction: Double) -> BudgetProgress {
    BudgetProgress(id: UUID(), categoryName: "Food & Dining", paletteSlot: 0, budgetMinor: 5000_00, spentMinor: 0, fraction: fraction, periodKey: "2026-08")
  }

  func testRowEmphasisIsFalseUnderNinetyPercent() {
    XCTAssertFalse(BudgetRowEmphasis.isAtOrAboveThreshold(progress(fraction: 0.89)))
  }

  func testRowEmphasisIsTrueAtExactlyNinetyPercent() {
    XCTAssertTrue(BudgetRowEmphasis.isAtOrAboveThreshold(progress(fraction: 0.9)))
  }

  func testRowEmphasisIsTrueOverOneHundredPercent() {
    XCTAssertTrue(BudgetRowEmphasis.isAtOrAboveThreshold(progress(fraction: 1.3)))
  }

  func testRowEmphasisIsFalseAtZeroSpend() {
    XCTAssertFalse(BudgetRowEmphasis.isAtOrAboveThreshold(progress(fraction: 0)))
  }

  func testSaveIntentIsRemoveAtZeroAmount() {
    XCTAssertEqual(BudgetSaveIntent.resolve(amountMinor: 0), .remove)
  }

  func testSaveIntentIsSetForPositiveAmount() {
    XCTAssertEqual(BudgetSaveIntent.resolve(amountMinor: 5000_00), .set(amountMinor: 5000_00))
  }

  func testFormGateRequiresACategory() {
    XCTAssertFalse(BudgetFormGate.isValid(categoryID: nil))
    XCTAssertTrue(BudgetFormGate.isValid(categoryID: UUID()))
  }

  func testRowSummaryLineIncludesCurrencyAndBothFigures() {
    let item = progress(fraction: 0.4)
    let line = BudgetRowSummary.line(for: item)
    XCTAssertTrue(line.contains("₹"))
    XCTAssertTrue(line.contains("of"))
  }
}
