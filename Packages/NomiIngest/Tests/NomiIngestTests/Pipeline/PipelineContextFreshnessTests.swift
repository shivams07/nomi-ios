import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// Shivam, 2026-09-11: "even if I set category, it stays uncategorised on
/// ledger."
///
/// Every path that decides a category is correct on a fresh read — merge ranks
/// manual above rule above none, `RuleEngine.apply` refuses a manual row, both
/// rule passes filter manual out. What none of them can survive is being handed
/// a *stale* read. The app builds one `SwiftDataPipelineStore` for the life of
/// the process, and the user's category is written by a different context
/// (`mainContext`, from the detail screen). If the store's context hands back
/// the copy of a row it materialised before that write, a second contributor
/// merging into the row writes `categoryID == nil` back over the user's choice
/// through `Transaction.apply(_:)`, which rewrites the category fields
/// unconditionally.
///
/// This is the sequence on a device with mail and statements both connected:
/// the alert arrives, the user categorises it, the statement row for the same
/// bank event is imported. A backfill re-scan does *not* reach this — the same
/// `SourceRef` makes the merge a no-op, so nothing is written.
///
/// One real container, both contexts on it, and the real `IngestPipeline` —
/// nothing here is a fake, because the defect under test lives in the gap
/// between two contexts and a fake store has no such gap.
///
/// **XCTest, and it has to stay XCTest**, for the reason
/// `SwiftDataPipelineStoreTests` gives: under swift-testing, constructing the
/// container traps.
@MainActor
final class PipelineContextFreshnessTests: XCTestCase {

  /// The app's schema, as `SwiftDataPipelineStoreTests` spells it out —
  /// `NomiModelContainer.schema` lives in NomiApp and this package cannot see
  /// it. Keep the two in the same order.
  private static func makeContainer() throws -> ModelContainer {
    let schema = Schema([
      Transaction.self,
      NomiCore.Category.self,
      Budget.self,
      BudgetAlertLog.self,
      Rule.self,
      Account.self,
      AccountBinding.self,
      ColumnMappingRecord.self,
    ])
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  func testAStatementRowMergingIntoACategorisedRowKeepsTheUsersCategory() async throws {
    let container = try Self.makeContainer()
    let main = container.mainContext
    let pipeline = IngestPipeline(
      store: SwiftDataPipelineStore(modelContainer: container),
      calendar: Fixture.calendar,
      now: Fixture.clock
    )

    let groceries = NomiCore.Category(name: "Groceries", symbolName: "cart", sortIndex: 1)
    main.insert(groceries)
    try main.save()

    let alert = Fixture.draft(source: .email, externalID: "uid-1")
    let statementRow = Fixture.draft(source: .file, externalID: "HDFC-20260820-0001")

    // The precondition the whole test rests on: the two drafts are one bank
    // event, so the second merges into the first on the exact tier.
    XCTAssertEqual(
      DraftDerivation.derive(alert, calendar: Fixture.calendar).dedupeKey,
      DraftDerivation.derive(statementRow, calendar: Fixture.calendar).dedupeKey
    )

    // (1) The mail alert becomes a row, through the pipeline's own context.
    try await pipeline.ingest([alert])

    // (2) The user categorises it from the detail screen, on mainContext.
    let beforeMerge = try main.fetch(FetchDescriptor<Transaction>())
    XCTAssertEqual(beforeMerge.count, 1)
    let row = try XCTUnwrap(beforeMerge.first)
    row.categoryID = groceries.id
    row.categorySourceRaw = CategorySource.manual.rawValue
    try main.save()

    // (3) The statement row for the same bank event is imported.
    let result = try await pipeline.ingest([statementRow])
    XCTAssertEqual(result.merged, 1, "the statement row must merge, not insert")
    XCTAssertEqual(result.created, 0)

    // (4) What the ledger reads.
    let onMain = try main.fetch(FetchDescriptor<Transaction>())
    XCTAssertEqual(onMain.count, 1)
    XCTAssertEqual(
      onMain.first?.mergedCount, 2,
      "mainContext: the merge did not reach this context, so the category assertions below prove nothing"
    )
    XCTAssertEqual(onMain.first?.categoryID, groceries.id, "mainContext: the user's category was reverted")
    XCTAssertEqual(onMain.first?.categorySourceRaw, CategorySource.manual.rawValue, "mainContext")

    // And what is actually in the store. A brand-new context has nothing
    // registered, so it cannot answer from memory — if mainContext and this
    // disagree, mainContext is the one that is stale.
    let onFresh = try ModelContext(container).fetch(FetchDescriptor<Transaction>())
    XCTAssertEqual(onFresh.count, 1)
    XCTAssertEqual(onFresh.first?.mergedCount, 2, "store")
    XCTAssertEqual(onFresh.first?.categoryID, groceries.id, "store: the user's category was reverted")
    XCTAssertEqual(onFresh.first?.categorySourceRaw, CategorySource.manual.rawValue, "store")
  }
}
