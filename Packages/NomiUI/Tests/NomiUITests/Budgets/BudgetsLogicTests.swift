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

  private var sampleProgress: [BudgetProgress] {
    [
      BudgetProgress(id: UUID(), categoryName: "Food & Dining", paletteSlot: 0, budgetMinor: 5000_00, spentMinor: 2000_00, fraction: 0.4, periodKey: "2026-08"),
      BudgetProgress(id: UUID(), categoryName: "Shopping", paletteSlot: 1, budgetMinor: 8000_00, spentMinor: 7200_00, fraction: 0.9, periodKey: "2026-08"),
      BudgetProgress(id: UUID(), categoryName: "Transport", paletteSlot: 2, budgetMinor: 2000_00, spentMinor: 2600_00, fraction: 1.3, periodKey: "2026-08"),
      BudgetProgress(id: UUID(), categoryName: "Bills & Utilities", paletteSlot: 3, budgetMinor: 3000_00, spentMinor: 0, fraction: 0.0, periodKey: "2026-08"),
    ]
  }

  func testBudgetTotalsComputeSumsAllRows() {
    let totals = BudgetTotals.compute(sampleProgress)
    XCTAssertEqual(totals?.spentMinor, 11800_00)
    XCTAssertEqual(totals?.budgetMinor, 18000_00)
    XCTAssertEqual(totals?.fraction ?? 0, 0.6556, accuracy: 0.0001)
  }

  func testBudgetTotalsComputeIsNilForEmpty() {
    XCTAssertNil(BudgetTotals.compute([]))
  }

  func testBudgetTotalsRemainingGoesNegativeWhenOverBudget() {
    let overBudgetRow = [BudgetProgress(id: UUID(), categoryName: "Transport", paletteSlot: 2, budgetMinor: 2000_00, spentMinor: 2600_00, fraction: 1.3, periodKey: "2026-08")]
    let totals = BudgetTotals.compute(overBudgetRow)
    XCTAssertEqual(totals?.remainingMinor, -600_00)
  }

  func testBudgetDaysLeftOnTheFourteenthOfSeptember() {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = 14
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let date = calendar.date(from: components)!
    XCTAssertEqual(BudgetDaysLeft.remaining(from: date, calendar: calendar), 17)
  }

  func testBudgetDaysLeftOnTheLastDayOfSeptember() {
    var components = DateComponents()
    components.year = 2026
    components.month = 9
    components.day = 30
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let date = calendar.date(from: components)!
    XCTAssertEqual(BudgetDaysLeft.remaining(from: date, calendar: calendar), 1)
  }

  func testBudgetPaceAssessment() {
    XCTAssertEqual(BudgetPace.assess(spentFraction: 0.34, elapsedFraction: 0.47), .under)
    XCTAssertEqual(BudgetPace.assess(spentFraction: 0.50, elapsedFraction: 0.47), .onPace)
    XCTAssertEqual(BudgetPace.assess(spentFraction: 0.70, elapsedFraction: 0.47), .ahead)
    XCTAssertEqual(BudgetPace.assess(spentFraction: 1.02, elapsedFraction: 0.47), .overBudget)
  }

  func testBudgetTileCaptionTextForRemainingAndOver() {
    XCTAssertTrue(BudgetTileCaption.text(3000_00).text.contains("3,000"))
    XCTAssertTrue(BudgetTileCaption.text(3000_00).text.contains("left"))
    XCTAssertFalse(BudgetTileCaption.text(3000_00).isOver)
    XCTAssertTrue(BudgetTileCaption.text(-600_00).text.contains("600"))
    XCTAssertTrue(BudgetTileCaption.text(-600_00).text.contains("over"))
    XCTAssertTrue(BudgetTileCaption.text(-600_00).isOver)
  }
}
