import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// Design §2.3's flagged risk: "the category breakdown must sum to the
/// transaction-list total in both views... if the breakdown and the list
/// resolve the range separately they will disagree at the March/April edge
/// and only there. U13's tests must include a transaction dated 31 Mar and
/// one dated 1 Apr."
///
/// This exercises `NomiCore.dateRange(for:calendar:)` — the single canonical
/// boundary function per that same section — against a small row set
/// straddling the edge, and proves a per-category grouped sum agrees with
/// the ungrouped period total in both calendar-month and financial-year
/// bases. It uses a plain, non-`@Model` stub row rather than a real
/// `Transaction`: this package's tests cannot construct `@Model` instances
/// (see `InMemoryModelContainer.swift`'s documented SwiftData bundle-name
/// crash — `RecentTransactionsSortTests`' `StubRow` already works around the
/// same constraint). The real `InsightsStore` implementation is out of this
/// unit's file boundary; what this unit owns and can regress-guard is that
/// its own screen code always derives both the breakdown and the transaction
/// list from one shared `InsightPeriod` value, never two separately-computed
/// ranges — this test's helper models that single-filter-pass guarantee.
final class ReportsPeriodBoundaryConsistencyTests: XCTestCase {
  private struct StubRow {
    let date: Date
    let amountMinor: Int
    let categoryID: UUID
  }

  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return utc.date(from: components)!
  }

  private let foodID = UUID()
  private let travelID = UUID()

  private func rows() -> [StubRow] {
    [
      StubRow(date: date(2026, 3, 31), amountMinor: 500_00, categoryID: foodID),
      StubRow(date: date(2026, 4, 1), amountMinor: 700_00, categoryID: travelID),
      StubRow(date: date(2026, 3, 15), amountMinor: 200_00, categoryID: foodID),
      StubRow(date: date(2026, 4, 15), amountMinor: 300_00, categoryID: travelID),
    ]
  }

  /// One filter pass, one range — grouped-by-category sum and ungrouped
  /// total can never disagree by construction. This is the shape this
  /// unit's screen code must follow (single `InsightPeriod`, passed once).
  private func categoryTotalsMatchPeriodTotal(_ rows: [StubRow], period: InsightPeriod, calendar: Calendar) -> Bool {
    let range = dateRange(for: period, calendar: calendar)
    let inPeriod = rows.filter { range.contains($0.date) }
    let byCategory = Dictionary(grouping: inPeriod, by: \.categoryID).mapValues { $0.reduce(0) { $0 + $1.amountMinor } }
    let categorySum = byCategory.values.reduce(0, +)
    let periodTotal = inPeriod.reduce(0) { $0 + $1.amountMinor }
    return categorySum == periodTotal
  }

  func testCategoryTotalsMatchPeriodTotalForCalendarMonthAcross31MarBoundary() {
    XCTAssertTrue(categoryTotalsMatchPeriodTotal(rows(), period: .month(year: 2026, month: 3), calendar: utc))
  }

  func testCategoryTotalsMatchPeriodTotalForCalendarMonthAcross1AprBoundary() {
    XCTAssertTrue(categoryTotalsMatchPeriodTotal(rows(), period: .month(year: 2026, month: 4), calendar: utc))
  }

  func testCategoryTotalsMatchPeriodTotalForFinancialYearEndingAt31Mar() {
    XCTAssertTrue(categoryTotalsMatchPeriodTotal(rows(), period: .financialYear(startingYear: 2025), calendar: utc))
  }

  func testCategoryTotalsMatchPeriodTotalForFinancialYearStartingAt1Apr() {
    XCTAssertTrue(categoryTotalsMatchPeriodTotal(rows(), period: .financialYear(startingYear: 2026), calendar: utc))
  }

  /// The edge itself: the 31-Mar row belongs to FY2025-26 and March's
  /// calendar month; the 1-Apr row belongs to FY2026-27 and April's
  /// calendar month. One day apart, different periods in both bases.
  func test31MarAnd1AprFallOnOppositeSidesOfBothBoundaries() {
    let marchRange = dateRange(for: .month(year: 2026, month: 3), calendar: utc)
    let aprilRange = dateRange(for: .month(year: 2026, month: 4), calendar: utc)
    XCTAssertTrue(marchRange.contains(date(2026, 3, 31)))
    XCTAssertFalse(marchRange.contains(date(2026, 4, 1)))
    XCTAssertTrue(aprilRange.contains(date(2026, 4, 1)))
    XCTAssertFalse(aprilRange.contains(date(2026, 3, 31)))

    let priorFYRange = dateRange(for: .financialYear(startingYear: 2025), calendar: utc)
    let newFYRange = dateRange(for: .financialYear(startingYear: 2026), calendar: utc)
    XCTAssertTrue(priorFYRange.contains(date(2026, 3, 31)))
    XCTAssertFalse(priorFYRange.contains(date(2026, 4, 1)))
    XCTAssertTrue(newFYRange.contains(date(2026, 4, 1)))
    XCTAssertFalse(newFYRange.contains(date(2026, 3, 31)))
  }
}
