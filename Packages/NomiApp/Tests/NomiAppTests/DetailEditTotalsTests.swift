import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp
@testable import NomiUI

/// S3b, R: saving a direction change from the Edit sheet moves the totals Home shows.
/// The sheet's model saves through the real `SwiftDataTransactionEditor` on an in-memory
/// store, and the totals are read the way Home reads them (`DashboardWiring.insights`).
@MainActor
final class DetailEditTotalsTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india
  private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  /// A row written straight to the context, keyed with the same NomiCore functions the
  /// editor and the store use (as `DirectionEditTests` does).
  private func seed(_ context: ModelContext, _ descriptionText: String, _ amountMinor: Int, _ direction: Direction) throws
    -> Transaction
  {
    let normalized = normalizeDescription(descriptionText)
    let row = Transaction(
      date: day,
      descriptionText: descriptionText,
      normalizedDescription: normalized,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      categorySourceRaw: CategorySource.none.rawValue,
      dedupeKey: makeDedupeKey(
        date: day, amountMinor: amountMinor, directionRaw: direction.rawValue, normalizedDescription: normalized)
    )
    context.insert(row)
    try context.save()
    return row
  }

  /// November holds SWIGGY ₹500 and CHAI ₹1,000, both debits: debit 150_000, credit 0.
  /// Saving SWIGGY as income from the sheet: debit 100_000, credit 50_000.
  func testSavingADebitAsIncomeFromTheSheetMovesHomesSpentAndIncome() throws {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    let editor = SwiftDataTransactionEditor(
      context: stack.context,
      coordinator: coordinator,
      now: { self.stamp },
      calendar: calendar,
      saveEdit: { context in try context.save() }
    )
    let insights = SwiftDataInsightsStore(context: stack.context, cache: cache)
    let swiggy = try seed(stack.context, "SWIGGY", 50_000, .debit)
    _ = try seed(stack.context, "CHAI", 100_000, .debit)
    let period = InsightPeriod.month(year: 2026, month: 11)

    guard case .loaded(let before) = DashboardWiring.insights(for: period, from: insights) else {
      return XCTFail("Home could not read the totals before the edit")
    }
    XCTAssertEqual(before.debitMinor, 150_000)
    XCTAssertEqual(before.creditMinor, 0)

    let model = TransactionEditModel(
      transactionID: swiggy.id, amountMinor: swiggy.amountMinor, date: swiggy.date,
      descriptionText: swiggy.descriptionText, note: swiggy.note, direction: swiggy.direction,
      isTransfer: swiggy.isTransfer, currencyCode: swiggy.currencyCode, merchantLabel: "SWIGGY",
      editor: editor, calendar: calendar)
    model.direction = .credit
    XCTAssertTrue(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertNil(model.errorMessage)

    guard case .loaded(let after) = DashboardWiring.insights(for: period, from: insights) else {
      return XCTFail("Home could not read the totals after the edit")
    }
    XCTAssertEqual(after.debitMinor, 100_000, "Spent should fall by ₹500")
    XCTAssertEqual(after.creditMinor, 50_000, "Income should rise by ₹500")
    XCTAssertEqual(before.debitMinor - after.debitMinor, 50_000)
    XCTAssertEqual(after.creditMinor - before.creditMinor, 50_000)
  }
}
