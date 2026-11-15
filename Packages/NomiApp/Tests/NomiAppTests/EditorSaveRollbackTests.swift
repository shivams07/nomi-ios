import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// R8b, step 5 and the `didWrite` follow-up. A save the editor cannot make leaves
/// nothing dirty for a later save to flush, and an unpairing reports the partner's
/// category. XCTest on a held `InMemoryStack`, as in `TransferPairRecheckTests`.
@MainActor
final class EditorSaveRollbackTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  /// Makes the editor's one save fail while `refuses` is true.
  private let gate = EditorSaveGate()
  private let calendar = NomiCalendar.india
  private let savingsAccount = UUID()
  private let cardAccount = UUID()

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private func makeEditor(
    observer: PartnerCategoryRecorder? = nil
  ) throws -> (SwiftDataTransactionEditor, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let coordinator = WriteCoordinator(cache: InsightsCache())
    if let observer { coordinator.setObserver(observer) }
    let gate = gate
    let editor = SwiftDataTransactionEditor(
      context: stack.context,
      coordinator: coordinator,
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      calendar: calendar,
      saveEdit: { context in
        if gate.refuses { throw EditorForcedSaveFailure() }
        try context.save()
      })
    return (editor, stack.context)
  }

  /// An auto-matched pair: ₹500 debit from savings, ₹500 credit to the card, the
  /// same day. Both legs carry the given categories.
  private func makeAutoPair(
    _ context: ModelContext,
    debitCategory: UUID? = nil,
    creditCategory: UUID? = nil
  ) throws -> (debit: Transaction, credit: Transaction) {
    let debit = Transaction(
      date: day,
      descriptionText: "NEFT TO CARD",
      normalizedDescription: normalizeDescription("NEFT TO CARD"),
      amountMinor: 50_000,
      directionRaw: Direction.debit.rawValue,
      categoryID: debitCategory,
      accountID: savingsAccount,
      dedupeKey: "debit"
    )
    let credit = Transaction(
      date: day,
      descriptionText: "NEFT FROM SAVINGS",
      normalizedDescription: normalizeDescription("NEFT FROM SAVINGS"),
      amountMinor: 50_000,
      directionRaw: Direction.credit.rawValue,
      categoryID: creditCategory,
      accountID: cardAccount,
      dedupeKey: "credit"
    )
    let group = TransferGroupID.make(debit.id, credit.id)
    debit.transferGroupID = group
    debit.transferSource = .auto
    credit.transferGroupID = group
    credit.transferSource = .auto
    context.insert(debit)
    context.insert(credit)
    try context.save()
    return (debit, credit)
  }

  private func fetchRow(_ context: ModelContext, _ id: UUID) throws -> Transaction {
    try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
  }

  // MARK: - update

  /// The amount edit breaks the match, so the editor writes the fields and unpairs,
  /// then the save fails. The rollback puts the stored row back, and nothing is left
  /// dirty for the next save to flush.
  func testAFailedAmountEditRollsBackAndLeavesNothingDirty() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)
    let group = try XCTUnwrap(debit.transferGroupID)
    gate.refuses = true

    XCTAssertThrowsError(
      try editor.update(debit.id, amountMinor: 50_100, date: day, descriptionText: "NEFT TO CARD", note: nil)
    ) { error in
      XCTAssertTrue(error is EditorForcedSaveFailure)
    }

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertEqual(d.amountMinor, 50_000, "the refused edit's amount was kept")
    XCTAssertEqual(d.transferGroupID, group, "the unpairing was kept")
    XCTAssertEqual(d.transferSourceRaw, TransferSource.auto.rawValue)
    XCTAssertEqual(c.transferGroupID, group)
    XCTAssertEqual(c.transferSourceRaw, TransferSource.auto.rawValue)
    XCTAssertFalse(context.hasChanges, "a failed save left changes for a later save to flush")
  }

  func testTheSameAmountEditSucceedsWhenTheSaveDoes() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)

    try editor.update(debit.id, amountMinor: 50_100, date: day, descriptionText: "NEFT TO CARD", note: nil)

    XCTAssertEqual(try fetchRow(context, debit.id).amountMinor, 50_100)
    XCTAssertNil(try fetchRow(context, debit.id).transferGroupID, "R8's unpairing")
    XCTAssertNil(try fetchRow(context, credit.id).transferGroupID)
    XCTAssertFalse(context.hasChanges)
  }

  // MARK: - setTransfer

  /// Unmarking an auto pair clears both legs and records `rejected` on the row. The
  /// save fails, so both legs stay paired and nothing is dirty.
  func testAFailedUnpairingRollsBackAndLeavesBothLegsPaired() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)
    let group = try XCTUnwrap(debit.transferGroupID)
    gate.refuses = true

    XCTAssertThrowsError(try editor.setTransfer(debit.id, isTransfer: false)) { error in
      XCTAssertTrue(error is EditorForcedSaveFailure)
    }

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertEqual(d.transferGroupID, group, "the debit lost its pair")
    XCTAssertEqual(c.transferGroupID, group, "the credit lost its pair")
    XCTAssertEqual(d.transferSourceRaw, TransferSource.auto.rawValue)
    XCTAssertFalse(context.hasChanges, "a failed unpairing left changes for a later save to flush")
  }

  // MARK: - didWrite

  /// The unpairing takes the partner out of the pair, so the partner's category is
  /// affected too and must reach `didWrite`. The debit has no category here, so the
  /// only way the credit's category can appear is through the partner.
  func testUnpairingAPartnerReportsItsCategoryToDidWrite() async throws {
    let food = UUID()
    let salary = UUID()
    let recorder = PartnerCategoryRecorder()
    let (editor, context) = try makeEditor(observer: recorder)
    let (debit, _) = try makeAutoPair(context, debitCategory: nil, creditCategory: salary)

    try editor.update(debit.id, amountMinor: 50_100, date: day, descriptionText: "NEFT TO CARD", note: nil)

    await fulfillment(of: [recorder.received], timeout: 2)
    let calls = recorder.calls
    XCTAssertTrue(
      calls.contains { $0.contains(salary) },
      "the partner's category \(salary) was not reported; got \(calls)")
    XCTAssertFalse(calls.contains { $0.contains(food) }, "an unrelated category was reported")
  }
}

/// A save the test refuses on purpose. File-private, so it does not clash with the
/// one `TransferDetectorSetAccountTests` defines.
private struct EditorForcedSaveFailure: Error {}

/// The switch for the editor's one save. A class, so the closure the editor keeps
/// and the test both see the same flag.
private final class EditorSaveGate {
  var refuses = false
}

/// Records each category set the coordinator hands the observer. Calls are
/// dispatched in a `Task`, so the test waits for the first one.
private final class PartnerCategoryRecorder: PostCommitObserver, @unchecked Sendable {
  let received = XCTestExpectation(description: "observer receives the affected categories")
  private let lock = NSLock()
  private var seen: [Set<UUID>] = []

  var calls: [Set<UUID>] {
    lock.lock()
    defer { lock.unlock() }
    return seen
  }

  func didCommit(affectedCategoryIDs: Set<UUID>) async {
    lock.lock()
    seen.append(affectedCategoryIDs)
    lock.unlock()
    received.fulfill()
  }
}
