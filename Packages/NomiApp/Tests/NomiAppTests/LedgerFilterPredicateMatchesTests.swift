import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiUI

/// U16 review gap: `LedgerFilterPredicate.matches(_:filter:within:)` carries the
/// category/uncategorized/search logic that a `#Predicate` could never hold
/// (two straight CI failures on that — see `LedgerFilterPredicate`'s doc
/// comment), but nothing exercised it against a real `Transaction`.
/// `NomiUITests` cannot — constructing an `@Model` instance there crashes
/// that package's runner (see `InMemoryModelContainer`'s note in NomiCore) —
/// so this lives here instead, same as `RecentTransactionsTests` and
/// `TransactionEditorTests` next to it, which already construct and insert
/// real `Transaction` rows under XCTest without issue.
///
/// G1 (DEC-04): `within` is the selected period, or nil for the queues and
/// search. Every call below says which.
@MainActor
final class LedgerFilterPredicateMatchesTests: XCTestCase {

  func testUncategorizedOnlyMatchesOnlyRowsWithNoCategory() throws {
    let context = try makeContext()
    let categorized = insert(Transaction(categoryID: UUID()), into: context)
    let uncategorized = insert(Transaction(categoryID: nil), into: context)
    let filter = TransactionFilter(uncategorizedOnly: true)

    XCTAssertFalse(LedgerFilterPredicate.matches(categorized, filter: filter, within: nil))
    XCTAssertTrue(LedgerFilterPredicate.matches(uncategorized, filter: filter, within: nil))
  }

  func testCategoryFilterMatchesOnlyTheSelectedCategories() throws {
    let context = try makeContext()
    let selected = UUID()
    let inCategory = insert(Transaction(categoryID: selected), into: context)
    let outOfCategory = insert(Transaction(categoryID: UUID()), into: context)
    let uncategorized = insert(Transaction(categoryID: nil), into: context)
    let filter = TransactionFilter(categoryIDs: [selected])

    XCTAssertTrue(LedgerFilterPredicate.matches(inCategory, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(outOfCategory, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(uncategorized, filter: filter, within: nil))
  }

  func testEmptyFilterMatchesEveryRow() throws {
    let context = try makeContext()
    let transaction = insert(
      Transaction(descriptionText: "anything", categoryID: UUID()), into: context)

    XCTAssertTrue(LedgerFilterPredicate.matches(transaction, filter: TransactionFilter(), within: nil))
  }

  func testSearchTextMatchesDescriptionMerchantOrCounterpartyVPACaseInsensitively() throws {
    let context = try makeContext()
    let byDescription = insert(Transaction(descriptionText: "Swiggy order #4021"), into: context)
    let byMerchant = insert(
      Transaction(descriptionText: "POS purchase", merchantName: "SWIGGY"), into: context)
    let byVPA = insert(
      Transaction(descriptionText: "UPI transfer", counterpartyVPA: "swiggy@icici"),
      into: context)
    let unrelated = insert(Transaction(descriptionText: "Zomato dinner"), into: context)
    let filter = TransactionFilter(searchText: "swiggy")

    XCTAssertTrue(LedgerFilterPredicate.matches(byDescription, filter: filter, within: nil))
    XCTAssertTrue(LedgerFilterPredicate.matches(byMerchant, filter: filter, within: nil))
    XCTAssertTrue(LedgerFilterPredicate.matches(byVPA, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(unrelated, filter: filter, within: nil))
  }

  func testNeedsReviewOnlyAdmitsOnlyFlaggedRows() throws {
    let context = try makeContext()
    let flagged = insert(Transaction(needsReview: true), into: context)
    let notFlagged = insert(Transaction(needsReview: false), into: context)
    let filter = TransactionFilter(needsReviewOnly: true)

    XCTAssertTrue(LedgerFilterPredicate.matches(flagged, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(notFlagged, filter: filter, within: nil))
  }

  func testSearchTextMatchesNoteEvenWhenDescriptionDoesNot() throws {
    let context = try makeContext()
    let matchesByNote = insert(
      Transaction(descriptionText: "POS purchase", note: "Split with Riya"), into: context)
    let unrelated = insert(
      Transaction(descriptionText: "POS purchase", note: "Groceries"), into: context)
    let filter = TransactionFilter(searchText: "Riya")

    XCTAssertTrue(LedgerFilterPredicate.matches(matchesByNote, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(unrelated, filter: filter, within: nil))
  }

  func testCategoryAndSearchBothApplyWhenBothAreSet() throws {
    let context = try makeContext()
    let categoryID = UUID()
    let matchesBoth = insert(
      Transaction(descriptionText: "Swiggy order", categoryID: categoryID), into: context)
    let matchesCategoryOnly = insert(
      Transaction(descriptionText: "Zomato order", categoryID: categoryID), into: context)
    let matchesSearchOnly = insert(
      Transaction(descriptionText: "Swiggy order", categoryID: UUID()), into: context)
    let filter = TransactionFilter(categoryIDs: [categoryID], searchText: "swiggy")

    XCTAssertTrue(LedgerFilterPredicate.matches(matchesBoth, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(matchesCategoryOnly, filter: filter, within: nil))
    XCTAssertFalse(LedgerFilterPredicate.matches(matchesSearchOnly, filter: filter, within: nil))
  }

  // MARK: - The period bound (G1, DEC-04 item 4)

  /// A row inside the period passes; a row before it or at its upper bound
  /// does not. The predicate already bounds the fetch; this is the in-memory
  /// second check, so a predicate mistake cannot show a row from another period.
  func testPeriodBoundAdmitsOnlyRowsInsideTheRange() throws {
    let context = try makeContext()
    let range = utc(2026, 10, 1)..<utc(2026, 11, 1)
    let inside = insert(Transaction(date: utc(2026, 10, 1)), into: context)
    let lastSecond = insert(Transaction(date: utc(2026, 10, 31, 23, 59, 59)), into: context)
    let before = insert(Transaction(date: utc(2026, 9, 30, 23, 59, 59)), into: context)
    let atUpperBound = insert(Transaction(date: utc(2026, 11, 1)), into: context)

    let filter = TransactionFilter()
    XCTAssertTrue(LedgerFilterPredicate.matches(inside, filter: filter, within: range))
    XCTAssertTrue(LedgerFilterPredicate.matches(lastSecond, filter: filter, within: range))
    XCTAssertFalse(LedgerFilterPredicate.matches(before, filter: filter, within: range))
    XCTAssertFalse(LedgerFilterPredicate.matches(atUpperBound, filter: filter, within: range))
  }

  /// nil is the queues and search: no date bound at all, so a row from any
  /// period is admitted (DEC-04 item 6: the Needs review queue is all-time).
  func testNilRangeAdmitsRowsFromAnyPeriod() throws {
    let context = try makeContext()
    let old = insert(Transaction(date: utc(2019, 3, 1), needsReview: true), into: context)
    let filter = TransactionFilter(needsReviewOnly: true)

    XCTAssertTrue(LedgerFilterPredicate.matches(old, filter: filter, within: nil))
  }

  /// The bound is applied to the whole filter, not just the date: a row inside
  /// the period that fails the chip is still out.
  func testPeriodBoundAndChipBothApply() throws {
    let context = try makeContext()
    let range = utc(2026, 10, 1)..<utc(2026, 11, 1)
    let inPeriodUncategorized = insert(Transaction(date: utc(2026, 10, 5), categoryID: nil), into: context)
    let inPeriodCategorized = insert(Transaction(date: utc(2026, 10, 5), categoryID: UUID()), into: context)
    let filter = TransactionFilter(uncategorizedOnly: true)

    XCTAssertTrue(LedgerFilterPredicate.matches(inPeriodUncategorized, filter: filter, within: range))
    XCTAssertFalse(LedgerFilterPredicate.matches(inPeriodCategorized, filter: filter, within: range))
  }

  // MARK: -

  /// UTC, fixed, so these dates mean the same thing on every machine.
  private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return calendar.date(from: components)!
  }

  @discardableResult
  private func insert(_ transaction: Transaction, into context: ModelContext) -> Transaction {
    context.insert(transaction)
    try? context.save()
    return transaction
  }

  private func makeContext() throws -> ModelContext {
    let schema = Schema([Transaction.self])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    return container.mainContext
  }
}
