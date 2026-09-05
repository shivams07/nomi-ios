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
    try editor.update(id, amountMinor: 45_00, date: newDate, descriptionText: "NEW DESCRIPTION")

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
    try editor.update(UUID(), amountMinor: 100, date: Date(), descriptionText: "x")
    XCTAssertTrue(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
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
