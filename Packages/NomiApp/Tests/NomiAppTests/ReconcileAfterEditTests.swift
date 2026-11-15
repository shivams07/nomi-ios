import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// I-11 Amendment 1. Reconcile groups rows by equal `dedupeKey` and deletes every row but one
/// survivor. So a user edit must never leave two non-manual rows with equal keys. These tests run
/// the real `IngestPipeline` over the real `SwiftDataPipelineStore` on an in-memory container, so the
/// rule is tested where it acts.
///
/// XCTest on an `InMemoryStack` held in a property for the life of the test.
@MainActor
final class ReconcileAfterEditTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private struct Fixture {
    let stack: InMemoryStack
    let editor: SwiftDataTransactionEditor
    let transactions: SwiftDataTransactionStore
    let pipeline: IngestPipeline

    var context: ModelContext { stack.context }
  }

  /// A row as the assertions read it: values only, read through a fresh context.
  private struct Stored {
    let id: UUID
    let dedupeKey: String
    let categoryID: UUID?
    let externalIDs: [String]
    let transferGroupID: UUID?
  }

  private func makeFixture() throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let coordinator = WriteCoordinator(cache: InsightsCache())
    return Fixture(
      stack: stack,
      editor: SwiftDataTransactionEditor(context: stack.context, coordinator: coordinator),
      transactions: SwiftDataTransactionStore(
        context: stack.context, coordinator: coordinator, calendar: calendar),
      pipeline: IngestPipeline(store: SwiftDataPipelineStore(modelContainer: stack.container))
    )
  }

  /// An email row written straight to the context, keyed the way the pipeline keys it.
  private func insertEmail(
    _ f: Fixture, _ description: String, amountMinor: Int, direction: Direction, externalID: String
  ) throws -> Transaction {
    let normalized = normalizeDescription(description)
    let row = Transaction(
      date: day,
      descriptionText: description,
      normalizedDescription: normalized,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      sourceRaw: IngestSource.email.rawValue,
      sourceRefs: [SourceRef(source: .email, externalID: externalID, capturedAt: day)],
      dedupeKey: makeDedupeKey(
        date: day, amountMinor: amountMinor, directionRaw: direction.rawValue,
        normalizedDescription: normalized)
    )
    f.context.insert(row)
    try f.context.save()
    return row
  }

  /// Every stored row, read through a fresh context on the container, so the read shows what the
  /// pipeline's own actor context saved.
  private func stored(_ f: Fixture) throws -> [Stored] {
    let context = ModelContext(f.stack.container)
    return try context.fetch(FetchDescriptor<Transaction>()).map { row in
      Stored(
        id: row.id,
        dedupeKey: row.dedupeKey,
        categoryID: row.categoryID,
        externalIDs: row.sourceRefs.map(\.externalID),
        transferGroupID: row.transferGroupID
      )
    }
  }

  /// `reconcile()` under the test deadline, as the spec's rule for every new await.
  private func reconcile(_ f: Fixture) async throws -> ReconcileResult {
    let pipeline = f.pipeline
    return try await withTestTimeout { try await pipeline.reconcile() }
  }

  // MARK: - Direction edit

  /// A debit and a credit with the same text and day have different keys, so nothing collapses. The
  /// user flips the credit to a debit. Its natural key now equals the first row's. The edited email
  /// row must not share it, so reconcile removes nothing and both rows survive.
  func testDirectionFlipNeverLetsReconcileDeleteAnEmailRow() async throws {
    let f = try makeFixture()
    let a = try insertEmail(f, "UPI OLA", amountMinor: 50_000, direction: .debit, externalID: "uid-a")
    let b = try insertEmail(f, "UPI OLA", amountMinor: 50_000, direction: .credit, externalID: "uid-b")
    XCTAssertNotEqual(a.dedupeKey, b.dedupeKey, "the fixture rows should not collide before the edit")

    try f.editor.setDirection(b.id, to: .debit)

    let result = try await reconcile(f)
    XCTAssertEqual(result.rowsRemoved, 0, "reconcile deleted a user-edited email row")
    let rows = try stored(f)
    XCTAssertEqual(Set(rows.map(\.id)), [a.id, b.id], "a row was removed by reconcile")
    XCTAssertEqual(Set(rows.map(\.dedupeKey)).count, 2, "the edited row shares a key with another row")
  }

  // MARK: - Amount edit

  /// Two email debits, same text and day, different amounts, so nothing collapses. The user corrects
  /// the second amount to match the first. Reconcile must leave both rows alone.
  func testAmountEditNeverLetsReconcileDeleteAnEmailRow() async throws {
    let f = try makeFixture()
    let a = try insertEmail(f, "UPI OLA", amountMinor: 50_000, direction: .debit, externalID: "uid-a")
    let b = try insertEmail(f, "UPI OLA", amountMinor: 45_000, direction: .debit, externalID: "uid-b")
    XCTAssertNotEqual(a.dedupeKey, b.dedupeKey)

    try f.editor.update(b.id, amountMinor: 50_000, date: day, descriptionText: "UPI OLA", note: nil)

    let result = try await reconcile(f)
    XCTAssertEqual(result.rowsRemoved, 0, "reconcile deleted a user-edited email row")
    XCTAssertEqual(Set(try stored(f).map(\.id)), [a.id, b.id])
  }

  // MARK: - Manual rows

  /// Two identical manual transfers. Each leg of each pair has the same natural key as its twin.
  /// Reconcile leaves a group of two manual rows alone, so all four rows survive, in two groups.
  func testTwoIdenticalManualTransfersSurviveReconcile() async throws {
    let f = try makeFixture()
    let from = UUID()
    let to = UUID()
    _ = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: from, toAccountID: to, note: nil)
    _ = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: from, toAccountID: to, note: nil)
    XCTAssertEqual(try stored(f).count, 4)

    let result = try await reconcile(f)
    XCTAssertEqual(result.rowsRemoved, 0, "reconcile removed a leg of a manual transfer")
    let rows = try stored(f)
    XCTAssertEqual(rows.count, 4)
    XCTAssertEqual(Set(rows.compactMap(\.transferGroupID)).count, 2, "the two transfers do not have two groups")
  }

  /// A manual row keeps the natural key: the key `makeDedupeKey` derives from its own fields, with
  /// no salt. The same holds after a plain edit.
  func testManualRowKeepsTheNaturalKeyAfterAnEdit() throws {
    let f = try makeFixture()
    let row = try f.transactions.add(
      ManualTransactionDraft(date: day, amountMinor: 50_000, descriptionText: "CHAI", direction: .credit))

    try f.editor.setDirection(row.id, to: .debit)
    XCTAssertEqual(
      try storedKey(f, row.id),
      makeDedupeKey(
        date: day, amountMinor: 50_000, directionRaw: "debit",
        normalizedDescription: normalizeDescription("CHAI")),
      "a manual row lost its natural key on a direction flip")

    try f.editor.update(row.id, amountMinor: 60_000, date: day, descriptionText: "CHAI", note: nil)
    XCTAssertEqual(
      try storedKey(f, row.id),
      makeDedupeKey(
        date: day, amountMinor: 60_000, directionRaw: "debit",
        normalizedDescription: normalizeDescription("CHAI")),
      "a manual row lost its natural key on an amount edit")
  }

  /// A manual credit is flipped to a debit that matches an email debit. Reconcile folds them: the
  /// manual row survives, keeps its category, and carries both source references. This is the
  /// section 10 pairing the amendment accepts.
  func testManualRowFlippedOntoAnAlertAbsorbsItKeepingTheUserCategory() async throws {
    let f = try makeFixture()
    let food = UUID()
    let manual = try f.transactions.add(
      ManualTransactionDraft(
        date: day, amountMinor: 50_000, descriptionText: "UPI OLA", direction: .credit, categoryID: food))
    let alert = try insertEmail(f, "UPI OLA", amountMinor: 50_000, direction: .debit, externalID: "uid-alert")
    let manualRef = try XCTUnwrap(manual.sourceRefs.first?.externalID)

    try f.editor.setDirection(manual.id, to: .debit)

    let result = try await reconcile(f)
    XCTAssertEqual(result.rowsRemoved, 1)
    let rows = try stored(f)
    XCTAssertEqual(rows.count, 1, "the alert and the manual row did not fold into one")
    let survivor = try XCTUnwrap(rows.first)
    XCTAssertEqual(survivor.id, manual.id, "the manual row did not survive the fold")
    XCTAssertEqual(survivor.categoryID, food, "the user's category was lost in the fold")
    XCTAssertEqual(Set(survivor.externalIDs), [manualRef, "uid-alert"], "a source reference was lost")
    XCTAssertNotEqual(alert.id, survivor.id)
  }

  // MARK: - Helpers

  private func storedKey(_ f: Fixture, _ id: UUID) throws -> String {
    let context = ModelContext(f.stack.container)
    let row = try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first)
    return row.dedupeKey
  }
}
