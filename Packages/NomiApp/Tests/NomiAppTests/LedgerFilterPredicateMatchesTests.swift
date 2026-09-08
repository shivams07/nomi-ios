import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiUI

/// U16 review gap: `LedgerFilterPredicate.matches(_:filter:)` carries the
/// category/uncategorized/search logic that a `#Predicate` could never hold
/// (two straight CI failures on that — see `LedgerFilterPredicate`'s doc
/// comment), but nothing exercised it against a real `Transaction`.
/// `NomiUITests` cannot — constructing an `@Model` instance there crashes
/// that package's runner (see `InMemoryModelContainer`'s note in NomiCore) —
/// so this lives here instead, same as `RecentTransactionsTests` and
/// `TransactionEditorTests` next to it, which already construct and insert
/// real `Transaction` rows under XCTest without issue.
@MainActor
final class LedgerFilterPredicateMatchesTests: XCTestCase {

  func testUncategorizedOnlyMatchesOnlyRowsWithNoCategory() throws {
    let context = try makeContext()
    let categorized = insert(Transaction(categoryID: UUID()), into: context)
    let uncategorized = insert(Transaction(categoryID: nil), into: context)
    let filter = TransactionFilter(uncategorizedOnly: true)

    XCTAssertFalse(LedgerFilterPredicate.matches(categorized, filter: filter))
    XCTAssertTrue(LedgerFilterPredicate.matches(uncategorized, filter: filter))
  }

  func testCategoryFilterMatchesOnlyTheSelectedCategories() throws {
    let context = try makeContext()
    let selected = UUID()
    let inCategory = insert(Transaction(categoryID: selected), into: context)
    let outOfCategory = insert(Transaction(categoryID: UUID()), into: context)
    let uncategorized = insert(Transaction(categoryID: nil), into: context)
    let filter = TransactionFilter(categoryIDs: [selected])

    XCTAssertTrue(LedgerFilterPredicate.matches(inCategory, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(outOfCategory, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(uncategorized, filter: filter))
  }

  func testEmptyFilterMatchesEveryRow() throws {
    let context = try makeContext()
    let transaction = insert(
      Transaction(descriptionText: "anything", categoryID: UUID()), into: context)

    XCTAssertTrue(LedgerFilterPredicate.matches(transaction, filter: TransactionFilter()))
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

    XCTAssertTrue(LedgerFilterPredicate.matches(byDescription, filter: filter))
    XCTAssertTrue(LedgerFilterPredicate.matches(byMerchant, filter: filter))
    XCTAssertTrue(LedgerFilterPredicate.matches(byVPA, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(unrelated, filter: filter))
  }

  func testNeedsReviewOnlyAdmitsOnlyFlaggedRows() throws {
    let context = try makeContext()
    let flagged = insert(Transaction(needsReview: true), into: context)
    let notFlagged = insert(Transaction(needsReview: false), into: context)
    let filter = TransactionFilter(needsReviewOnly: true)

    XCTAssertTrue(LedgerFilterPredicate.matches(flagged, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(notFlagged, filter: filter))
  }

  func testSearchTextMatchesNoteEvenWhenDescriptionDoesNot() throws {
    let context = try makeContext()
    let matchesByNote = insert(
      Transaction(descriptionText: "POS purchase", note: "Split with Riya"), into: context)
    let unrelated = insert(
      Transaction(descriptionText: "POS purchase", note: "Groceries"), into: context)
    let filter = TransactionFilter(searchText: "Riya")

    XCTAssertTrue(LedgerFilterPredicate.matches(matchesByNote, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(unrelated, filter: filter))
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

    XCTAssertTrue(LedgerFilterPredicate.matches(matchesBoth, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(matchesCategoryOnly, filter: filter))
    XCTAssertFalse(LedgerFilterPredicate.matches(matchesSearchOnly, filter: filter))
  }

  // MARK: -

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
