import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// Exercises the ledger's pure grouping/filter/magnitude math against plain
/// stubs, never a real `Transaction` — this package's CI runner cannot
/// construct `@Model` instances headlessly (see `InMemoryModelContainer`'s
/// note in NomiCore). `LedgerRow` exists precisely so this can be verified
/// without one, same pattern as `RecentTransactionsSortTests`' `StubRow`.
private struct StubRow: LedgerRow, Equatable {
  let label: String
  let date: Date
  let amountMinor: Int
  let direction: Direction
  let categoryID: UUID?
}

/// Fixed calendar/timezone throughout — CI runs UTC and Shivam does not, so
/// a day-boundary test that trusts `.current` passes here and fails there.
private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
  return calendar
}()

private func date(_ string: String) -> Date {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.date(from: string)!
}

final class LedgerGroupingTests: XCTestCase {
  func testGroupsByCalendarDay() {
    let rows = [
      StubRow(label: "a", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "b", date: date("2026-08-19"), amountMinor: 200, direction: .debit, categoryID: nil),
      StubRow(label: "c", date: date("2026-08-20"), amountMinor: 300, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].rows.map(\.label), ["a", "c"], "same-day rows preserve source order")
    XCTAssertEqual(groups[1].rows.map(\.label), ["b"])
  }

  func testPreservesDayOrderFromFirstEncounter() {
    // Fed newest-first, as `LedgerScreen`'s `@Query` sort produces — the
    // first day encountered (20th) must sort before the second (19th).
    let rows = [
      StubRow(label: "newest", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "older", date: date("2026-08-19"), amountMinor: 100, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.map { calendar.startOfDay(for: $0.day) }, [date("2026-08-20"), date("2026-08-19")])
  }

  func testYearBoundaryProducesDistinctDays() {
    let rows = [
      StubRow(label: "dec31", date: date("2025-12-31"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "jan1", date: date("2026-01-01"), amountMinor: 100, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 2, "a year boundary must not collapse two distinct days into one")
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertTrue(LedgerGrouping.byDay([StubRow](), calendar: calendar).isEmpty)
  }

  func testDayTotalIsNetOfCreditsAndDebits() {
    let rows = [
      StubRow(label: "debit", date: date("2026-08-20"), amountMinor: 500, direction: .debit, categoryID: nil),
      StubRow(label: "credit", date: date("2026-08-20"), amountMinor: 200, direction: .credit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.first?.totalMinor, -300, "the day's total matches the sum of its rows")
  }

  func testDayTotalOfAllCreditsIsPositive() {
    let rows = [
      StubRow(label: "credit", date: date("2026-08-20"), amountMinor: 500, direction: .credit, categoryID: nil),
    ]
    XCTAssertEqual(LedgerGrouping.byDay(rows, calendar: calendar).first?.totalMinor, 500)
  }
}

final class LedgerFilteringTests: XCTestCase {
  private let foodID = UUID()
  private let shoppingID = UUID()

  private func rows() -> [StubRow] {
    [
      StubRow(label: "food", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: foodID),
      StubRow(label: "shopping", date: date("2026-08-20"), amountMinor: 200, direction: .debit, categoryID: shoppingID),
      StubRow(label: "uncategorized", date: date("2026-08-20"), amountMinor: 300, direction: .debit, categoryID: nil),
    ]
  }

  func testAllReturnsEveryRow() {
    XCTAssertEqual(LedgerFiltering.apply(rows(), selection: .all).count, 3)
  }

  func testCategorySelectionKeepsOnlyThatCategory() {
    let result = LedgerFiltering.apply(rows(), selection: .category(foodID))
    XCTAssertEqual(result.map(\.label), ["food"])
  }

  func testUncategorizedSelectionKeepsOnlyNilCategory() {
    let result = LedgerFiltering.apply(rows(), selection: .uncategorized)
    XCTAssertEqual(result.map(\.label), ["uncategorized"])
  }

  func testCategoryWithNoMatchesReturnsEmpty() {
    XCTAssertTrue(LedgerFiltering.apply(rows(), selection: .category(UUID())).isEmpty)
  }
}

final class LedgerMagnitudeTests: XCTestCase {
  func testFractionIsRatioToMax() {
    XCTAssertEqual(LedgerMagnitude.fraction(amountMinor: 50, maxAmountMinor: 100), 0.5)
  }

  func testFractionAtMaxIsOne() {
    XCTAssertEqual(LedgerMagnitude.fraction(amountMinor: 100, maxAmountMinor: 100), 1)
  }

  func testFractionClampsAboveOne() {
    XCTAssertEqual(LedgerMagnitude.fraction(amountMinor: 150, maxAmountMinor: 100), 1)
  }

  func testZeroMaxReturnsZeroRatherThanDividingByZero() {
    XCTAssertEqual(LedgerMagnitude.fraction(amountMinor: 50, maxAmountMinor: 0), 0)
  }

  func testUsesAbsoluteValue() {
    XCTAssertEqual(LedgerMagnitude.fraction(amountMinor: -50, maxAmountMinor: 100), 0.5)
  }
}

/// `LedgerScreen.dayHeader` renders `LedgerDayHeaderText.string(for:relativeTo:)`
/// — a pure wrapper defined in `LedgerScreen.swift` itself, not the general
/// `NomiFormatters.dayMonthAdaptive` it wraps, so this exercises this unit's
/// own code. A test against the formatter alone would pass whether or not
/// `dayHeader` was ever wired up to it.
final class LedgerDayHeaderTests: XCTestCase {
  func testDayHeaderOmitsYearForACurrentYearGroup() {
    let reference = date("2026-09-03")
    let sameYear = date("2026-08-20")
    let text = LedgerDayHeaderText.string(for: sameYear, relativeTo: reference)
    XCTAssertFalse(text.contains("2026"))
  }

  func testDayHeaderIncludesYearForAPriorYearGroup() {
    let reference = date("2026-09-03")
    let priorYear = date("2025-12-31")
    let text = LedgerDayHeaderText.string(for: priorYear, relativeTo: reference)
    XCTAssertTrue(text.contains("2025"))
  }
}

final class LedgerDayTotalTextTests: XCTestCase {
  func testPositiveTotalGetsPlusSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: 500), "+" + NomiFormatters.amountString(minor: 500))
  }

  func testNegativeTotalGetsMinusSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: -500), "-" + NomiFormatters.amountString(minor: 500))
  }

  func testZeroTotalHasNoSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: 0), NomiFormatters.amountString(minor: 0))
  }
}

/// F1: the ledger no longer loads the whole transaction table. Fixed `now`
/// and an explicit IST `calendar` throughout — same reasoning as every other
/// date-bearing test in this file: CI runs UTC and Shivam does not.
final class LedgerWindowTests: XCTestCase {
  private let now = date("2026-09-05")

  func testStepZeroIsNinetyDaysBack() {
    let expected = calendar.date(byAdding: .day, value: -90, to: now)!
    XCTAssertEqual(LedgerWindow.since(for: 0, now: now, calendar: calendar), expected)
  }

  func testStepOneWidensToOneHundredEightyDaysBack() {
    let expected = calendar.date(byAdding: .day, value: -180, to: now)!
    XCTAssertEqual(LedgerWindow.since(for: 1, now: now, calendar: calendar), expected)
  }

  func testStepThreeWidensToThreeHundredSixtyDaysBack() {
    let expected = calendar.date(byAdding: .day, value: -360, to: now)!
    XCTAssertEqual(LedgerWindow.since(for: 3, now: now, calendar: calendar), expected)
  }
}
