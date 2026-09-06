import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// XCTest, not swift-testing, same reason as `AccountStoreTests` next to it:
/// a `ModelContainer` traps under the swift-testing runner (see
/// `InMemoryModelContainer`'s note in NomiCore).
@MainActor
final class TransactionEditorTests: XCTestCase {

  /// The whole contract in one test: amount, date and description rewrite;
  /// `dedupeKey` re-derives from the new values through the same public
  /// functions the pipeline uses; everything editing has no business
  /// touching stays exactly as it was.
  func testUpdateRewritesTheEditedFieldsAndRecomputesDedupeKeyLeavingEverythingElseAlone() throws {
    let (editor, context, _) = try makeEditor()
    let categoryID = UUID()
    let accountID = UUID()
    let sourceRefs = [
      SourceRef(source: .email, externalID: "uid-1", capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
    ]

    let transaction = Transaction(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "OLD DESCRIPTION",
      normalizedDescription: normalizeDescription("OLD DESCRIPTION"),
      amountMinor: 0,
      directionRaw: Direction.debit.rawValue,
      categoryID: categoryID,
      accountID: accountID,
      sourceRaw: IngestSource.email.rawValue,
      sourceRefs: sourceRefs,
      mergedCount: 2,
      needsReview: true,
      dedupeKey: "stale-key"
    )
    context.insert(transaction)
    try context.save()

    let id = transaction.id
    let newDate = Date(timeIntervalSince1970: 1_701_000_000)
    try editor.update(id, amountMinor: 45_00, date: newDate, descriptionText: "NEW DESCRIPTION", note: nil)

    let refetched = try XCTUnwrap(
      context.fetch(
        FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
      ).first
    )

    XCTAssertEqual(refetched.amountMinor, 45_00)
    XCTAssertEqual(refetched.date, newDate)
    XCTAssertEqual(refetched.descriptionText, "NEW DESCRIPTION")
    XCTAssertEqual(refetched.normalizedDescription, normalizeDescription("NEW DESCRIPTION"))

    let expectedKey = makeDedupeKey(
      date: newDate,
      amountMinor: 45_00,
      directionRaw: Direction.debit.rawValue,
      normalizedDescription: normalizeDescription("NEW DESCRIPTION")
    )
    XCTAssertEqual(refetched.dedupeKey, expectedKey, "the key must be byte-identical to a fresh computation")

    XCTAssertTrue(refetched.needsReview, "editing amount/date/description is not a review dismissal")
    XCTAssertEqual(refetched.categoryID, categoryID)
    XCTAssertEqual(refetched.accountID, accountID)
    XCTAssertEqual(refetched.sourceRefs, sourceRefs)
    XCTAssertEqual(refetched.mergedCount, 2)
  }

  func testUpdateOnAMissingRowDoesNothing() throws {
    let (editor, context, _) = try makeEditor()
    try editor.update(UUID(), amountMinor: 100, date: Date(), descriptionText: "x", note: "unrelated")
    XCTAssertTrue(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
  }

  /// U24's own acceptance test: a note stores, and touches neither
  /// derivation `note` is deliberately excluded from.
  func testUpdateWithANoteStoresItAndLeavesDedupeKeyAndNormalizedDescriptionUnchanged() throws {
    let (editor, context, _) = try makeEditor()
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let normalized = normalizeDescription("COFFEE SHOP")
    let originalKey = makeDedupeKey(
      date: date, amountMinor: 450, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
    )
    let transaction = Transaction(
      date: date,
      descriptionText: "COFFEE SHOP",
      normalizedDescription: normalized,
      amountMinor: 450,
      directionRaw: Direction.debit.rawValue,
      dedupeKey: originalKey
    )
    context.insert(transaction)
    try context.save()

    let id = transaction.id
    try editor.update(id, amountMinor: 450, date: date, descriptionText: "COFFEE SHOP", note: "Split with Riya")

    let refetched = try XCTUnwrap(
      context.fetch(
        FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
      ).first
    )

    XCTAssertEqual(refetched.note, "Split with Riya")
    XCTAssertEqual(refetched.dedupeKey, originalKey, "a note must not re-key an already-keyed row")
    XCTAssertEqual(refetched.normalizedDescription, normalized, "a note is not the source's narration")
  }

  func testUpdateWithANilNoteClearsAnExistingOne() throws {
    let (editor, context, _) = try makeEditor()
    let transaction = Transaction(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "COFFEE SHOP",
      amountMinor: 450,
      directionRaw: Direction.debit.rawValue,
      dedupeKey: "key",
      note: "Split with Riya"
    )
    context.insert(transaction)
    try context.save()

    let id = transaction.id
    try editor.update(
      id, amountMinor: 450, date: transaction.date, descriptionText: "COFFEE SHOP", note: nil)

    let refetched = try XCTUnwrap(
      context.fetch(
        FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
      ).first
    )
    XCTAssertNil(refetched.note)
  }

  // MARK: -

  private func makeEditor() throws -> (SwiftDataTransactionEditor, ModelContext, WriteCoordinator) {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    let context = container.mainContext
    let coordinator = WriteCoordinator(cache: InsightsCache())
    let editor = SwiftDataTransactionEditor(context: context, coordinator: coordinator)
    return (editor, context, coordinator)
  }
}
