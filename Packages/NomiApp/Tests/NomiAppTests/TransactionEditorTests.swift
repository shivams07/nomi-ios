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

  // MARK: - setTransfer (DEC-05)

  private func insertRow(
    _ context: ModelContext,
    amount: Int,
    direction: Direction,
    account: UUID?,
    dayOffset: Int = 0,
    key: String
  ) throws -> Transaction {
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let row = Transaction(
      date: base.addingTimeInterval(Double(dayOffset) * 86_400),
      descriptionText: "X",
      normalizedDescription: "X",
      amountMinor: amount,
      directionRaw: direction.rawValue,
      accountID: account,
      dedupeKey: key
    )
    context.insert(row)
    try context.save()
    return row
  }

  private func fetchRow(_ context: ModelContext, _ id: UUID) throws -> Transaction {
    try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
  }

  /// A-05 fixture F's pair: savings debit, card credit, two days apart.
  func testMarkingOneLegMarksTheMatchingPairAsOneGroup() throws {
    let (editor, context, _) = try makeEditor()
    let savings = UUID()
    let card = UUID()
    let debit = try insertRow(context, amount: 2_000_000, direction: .debit, account: savings, key: "a")
    let credit = try insertRow(context, amount: 2_000_000, direction: .credit, account: card, dayOffset: 1, key: "b")

    try editor.setTransfer(debit.id, isTransfer: true)

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertEqual(d.transferGroupID, TransferGroupID.make(debit.id, credit.id))
    XCTAssertEqual(c.transferGroupID, d.transferGroupID, "both legs share one group")
    XCTAssertEqual(d.transferSource, .manual)
    XCTAssertEqual(c.transferSource, .manual)
  }

  func testMarkingWithNoPartnerMarksTheRowAlone() throws {
    let (editor, context, _) = try makeEditor()
    let row = try insertRow(context, amount: 500_00, direction: .debit, account: UUID(), key: "solo")

    try editor.setTransfer(row.id, isTransfer: true)

    let refetched = try fetchRow(context, row.id)
    XCTAssertEqual(refetched.transferGroupID, TransferGroupID.make(single: row.id))
    XCTAssertEqual(refetched.transferSource, .manual)
  }

  func testUnmarkingClearsBothLegsAndRejectsOnlyTheTouchedRow() throws {
    let (editor, context, _) = try makeEditor()
    let debit = try insertRow(context, amount: 2_000_000, direction: .debit, account: UUID(), key: "a")
    let credit = try insertRow(context, amount: 2_000_000, direction: .credit, account: UUID(), dayOffset: 1, key: "b")
    try editor.setTransfer(debit.id, isTransfer: true)

    try editor.setTransfer(credit.id, isTransfer: false)

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertNil(d.transferGroupID, "the partner's leg is cleared with the touched row's group")
    XCTAssertNil(d.transferSource)
    XCTAssertNil(c.transferGroupID)
    XCTAssertEqual(c.transferSource, .rejected)
  }

  /// A rejected row is the user's choice, and the user can change it: marking
  /// it again pairs it with its free partner.
  func testARejectedRowCanBeMarkedAgain() throws {
    let (editor, context, _) = try makeEditor()
    let debit = try insertRow(context, amount: 2_000_000, direction: .debit, account: UUID(), key: "a")
    let credit = try insertRow(context, amount: 2_000_000, direction: .credit, account: UUID(), dayOffset: 1, key: "b")
    try editor.setTransfer(debit.id, isTransfer: false)
    XCTAssertEqual(try fetchRow(context, debit.id).transferSource, .rejected)

    try editor.setTransfer(debit.id, isTransfer: true)

    XCTAssertEqual(try fetchRow(context, debit.id).transferGroupID, TransferGroupID.make(debit.id, credit.id))
    XCTAssertEqual(try fetchRow(context, debit.id).transferSource, .manual)
  }

  func testMarkingARowThatIsAlreadyALegChangesNothing() throws {
    let (editor, context, _) = try makeEditor()
    let debit = try insertRow(context, amount: 2_000_000, direction: .debit, account: UUID(), key: "a")
    _ = try insertRow(context, amount: 2_000_000, direction: .credit, account: UUID(), dayOffset: 1, key: "b")
    try editor.setTransfer(debit.id, isTransfer: true)
    let before = try fetchRow(context, debit.id).transferGroupID

    try editor.setTransfer(debit.id, isTransfer: true)

    XCTAssertEqual(try fetchRow(context, debit.id).transferGroupID, before)
  }

  /// A-05 item 12. A mark changes the next read of the insights with no manual
  /// refresh: the write went through `WriteCoordinator`, which drops the cache.
  func testSetTransferInvalidatesTheInsightsCache() throws {
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
    let calendar = NomiCalendar.india
    let fixed = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    let editor = SwiftDataTransactionEditor(context: context, coordinator: coordinator)
    let insights = SwiftDataInsightsStore(context: context, cache: cache, calendar: calendar, now: { fixed })

    let november10 = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    let debit = Transaction(
      date: november10,
      descriptionText: "X",
      normalizedDescription: "X",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      accountID: UUID(),
      dedupeKey: "a"
    )
    let credit = Transaction(
      date: november10.addingTimeInterval(86_400),
      descriptionText: "Y",
      normalizedDescription: "Y",
      amountMinor: 2_000_000,
      directionRaw: Direction.credit.rawValue,
      accountID: UUID(),
      dedupeKey: "b"
    )
    context.insert(debit)
    context.insert(credit)
    try context.save()
    let period = InsightPeriod.month(year: 2026, month: 11)
    XCTAssertEqual(try insights.insights(for: period).debitMinor, 2_000_000, "warms the cache")

    try editor.setTransfer(debit.id, isTransfer: true)

    XCTAssertEqual(try insights.insights(for: period).debitMinor, 0, "the mark is visible on the next read")
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
