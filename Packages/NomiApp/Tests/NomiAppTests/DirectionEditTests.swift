import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// B2, I-11. Flipping a row between debit and credit moves the period's spent and income
/// totals, re-keys the row, refuses a transfer leg, and rolls back when its save fails.
///
/// XCTest on an `InMemoryStack` held in a property for the life of the test.
@MainActor
final class DirectionEditTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india
  private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private struct Fixture {
    let editor: SwiftDataTransactionEditor
    let transactions: SwiftDataTransactionStore
    let insights: SwiftDataInsightsStore
    let context: ModelContext
  }

  /// One container and one cache shared by the editor, the store that writes transfers, and the
  /// insights reader, for the reason `AccountStoreTests` gives.
  private func makeFixture(
    observer: DirectionCategoryRecorder? = nil,
    gate: DirectionSaveGate = DirectionSaveGate()
  ) throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    if let observer { coordinator.setObserver(observer) }
    let fixedNow = stamp
    let editor = SwiftDataTransactionEditor(
      context: stack.context,
      coordinator: coordinator,
      now: { fixedNow },
      calendar: calendar,
      saveEdit: { context in
        if gate.refuses { throw DirectionForcedSaveFailure() }
        try context.save()
      }
    )
    let transactions = SwiftDataTransactionStore(
      context: stack.context,
      coordinator: coordinator,
      calendar: calendar,
      now: { fixedNow }
    )
    return Fixture(
      editor: editor,
      transactions: transactions,
      insights: SwiftDataInsightsStore(context: stack.context, cache: cache),
      context: stack.context
    )
  }

  /// A row written straight to the context, so the test controls its date and key. The key is
  /// derived with the same NomiCore functions the editor and the store use.
  private func seed(
    _ context: ModelContext,
    descriptionText: String,
    amountMinor: Int,
    direction: Direction,
    categoryID: UUID? = nil
  ) throws -> Transaction {
    let normalized = normalizeDescription(descriptionText)
    let row = Transaction(
      date: day,
      descriptionText: descriptionText,
      normalizedDescription: normalized,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      categoryID: categoryID,
      categorySourceRaw: categoryID == nil ? CategorySource.none.rawValue : CategorySource.manual.rawValue,
      dedupeKey: makeDedupeKey(
        date: day, amountMinor: amountMinor, directionRaw: direction.rawValue, normalizedDescription: normalized)
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

  // MARK: - Totals

  /// Hand computed. November holds SWIGGY ₹500 (50_000) and CHAI ₹1,000 (100_000), both debits:
  /// debit 150_000, credit 0. Flip SWIGGY to credit: debit 100_000 (₹1,000), credit 50_000 (₹500).
  /// So debit falls by 50_000 and credit rises by 50_000. Net goes from −150_000 to −50_000.
  func testADebitFlippedToCreditMovesFiveHundredFromDebitToCredit() throws {
    let f = try makeFixture()
    let swiggy = try seed(f.context, descriptionText: "SWIGGY", amountMinor: 50_000, direction: .debit)
    _ = try seed(f.context, descriptionText: "CHAI", amountMinor: 100_000, direction: .debit)

    let period = InsightPeriod.month(year: 2026, month: 11)
    let before = try f.insights.insights(for: period)
    XCTAssertEqual(before.debitMinor, 150_000)
    XCTAssertEqual(before.creditMinor, 0)

    try f.editor.setDirection(swiggy.id, to: .credit)

    let after = try f.insights.insights(for: period)
    XCTAssertEqual(after.debitMinor, 100_000)
    XCTAssertEqual(after.creditMinor, 50_000)
    XCTAssertEqual(before.debitMinor - after.debitMinor, 50_000, "debit did not fall by ₹500")
    XCTAssertEqual(after.creditMinor - before.creditMinor, 50_000, "credit did not rise by ₹500")
    XCTAssertEqual(after.netMinor, -50_000)
  }

  // MARK: - Key

  /// Direction is part of `dedupeKey`, so a flip re-keys the row. The new key is the one
  /// `makeDedupeKey` derives for the credit, and it is not the old one.
  func testTheFlipRederivesTheDedupeKey() throws {
    let f = try makeFixture()
    let row = try seed(f.context, descriptionText: "SWIGGY", amountMinor: 50_000, direction: .debit)
    let debitKey = row.dedupeKey

    try f.editor.setDirection(row.id, to: .credit)

    let stored = try fetchRow(f.context, row.id)
    let expected = makeDedupeKey(
      date: day, amountMinor: 50_000, directionRaw: "credit",
      normalizedDescription: normalizeDescription("SWIGGY"))
    XCTAssertEqual(stored.directionRaw, "credit")
    XCTAssertEqual(stored.dedupeKey, expected)
    XCTAssertNotEqual(stored.dedupeKey, debitKey)
  }

  // MARK: - Refusal

  /// A transfer leg is refused, and the leg is unchanged: direction, key and `updatedAt`.
  /// Both legs are tried, so neither side of a pair can be flipped alone.
  func testATransferLegRefusesTheFlipAndIsUnchanged() throws {
    let f = try makeFixture()
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)

    for leg in [debit, credit] {
      let directionBefore = leg.directionRaw
      let keyBefore = leg.dedupeKey
      let updatedBefore = leg.updatedAt

      XCTAssertThrowsError(try f.editor.setDirection(leg.id, to: leg.direction == .debit ? .credit : .debit)) { error in
        XCTAssertEqual(error as? TransactionEditError, .transferLeg)
      }

      let stored = try fetchRow(f.context, leg.id)
      XCTAssertEqual(stored.directionRaw, directionBefore, "a refused flip changed the direction")
      XCTAssertEqual(stored.dedupeKey, keyBefore, "a refused flip re-keyed the leg")
      XCTAssertEqual(stored.updatedAt, updatedBefore, "a refused flip touched updatedAt")
    }
    XCTAssertFalse(f.context.hasChanges)
  }

  /// An id that names no row is a no-op, the shape `update` has.
  func testAnUnknownIdIsANoOp() throws {
    let f = try makeFixture()
    _ = try seed(f.context, descriptionText: "SWIGGY", amountMinor: 50_000, direction: .debit)

    XCTAssertNoThrow(try f.editor.setDirection(UUID(), to: .credit))
    XCTAssertFalse(f.context.hasChanges)
  }

  // MARK: - Save

  /// The save fails. The stored row keeps its direction and key, and nothing is dirty.
  func testAFailedSaveRollsTheFlipBack() throws {
    let gate = DirectionSaveGate()
    let f = try makeFixture(gate: gate)
    let row = try seed(f.context, descriptionText: "SWIGGY", amountMinor: 50_000, direction: .debit)
    let keyBefore = row.dedupeKey
    gate.refuses = true

    XCTAssertThrowsError(try f.editor.setDirection(row.id, to: .credit)) { error in
      XCTAssertTrue(error is DirectionForcedSaveFailure)
    }

    let stored = try fetchRow(f.context, row.id)
    XCTAssertEqual(stored.directionRaw, Direction.debit.rawValue, "the refused flip was kept")
    XCTAssertEqual(stored.dedupeKey, keyBefore, "the refused flip re-keyed the row")
    XCTAssertFalse(f.context.hasChanges, "a failed flip left changes for a later save to flush")
  }

  // MARK: - didWrite

  /// The flip changes the category's spend, so the row's category reaches `didWrite`.
  func testTheFlipReportsTheRowsCategoryToDidWrite() async throws {
    let food = UUID()
    let recorder = DirectionCategoryRecorder()
    let f = try makeFixture(observer: recorder)
    let row = try seed(
      f.context, descriptionText: "SWIGGY", amountMinor: 50_000, direction: .debit, categoryID: food)

    try f.editor.setDirection(row.id, to: .credit)

    await fulfillment(of: [recorder.received], timeout: 2)
    XCTAssertTrue(
      recorder.calls.contains { $0.contains(food) },
      "the row's category \(food) was not reported; got \(recorder.calls)")
  }
}

/// A save the test refuses on purpose. Private to this file.
private struct DirectionForcedSaveFailure: Error {}

/// The switch for the editor's one save. A class, so the closure and the test share the flag.
private final class DirectionSaveGate {
  var refuses = false
}

/// Records each category set the coordinator hands the observer. Calls are dispatched in a
/// `Task`, so the test waits for the first one.
private final class DirectionCategoryRecorder: PostCommitObserver, @unchecked Sendable {
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
