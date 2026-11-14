import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// R8. The store refuses an out-of-range transaction amount before it writes
/// anything. XCTest, not swift-testing, because a `ModelContainer` traps under the
/// swift-testing runner. Each stack is held in a stored property for the life of
/// the test, not in a local (see `InMemoryStack`).
@MainActor
final class AmountValidationStoreTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

  private func makeStore() throws -> (SwiftDataTransactionStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let store = SwiftDataTransactionStore(
      context: stack.context,
      coordinator: WriteCoordinator(cache: InsightsCache()),
      now: { [fixedNow] in fixedNow }
    )
    return (store, stack.context)
  }

  private func makeEditor() throws -> (SwiftDataTransactionEditor, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let editor = SwiftDataTransactionEditor(
      context: stack.context,
      coordinator: WriteCoordinator(cache: InsightsCache()),
      now: { [fixedNow] in fixedNow },
      calendar: NomiCalendar.india
    )
    return (editor, stack.context)
  }

  func testAddRefusesZeroNegativeAndAboveTheMaximumAndWritesNothing() throws {
    for amount in [0, -5, 100_000_000_001] {
      let (store, context) = try makeStore()
      XCTAssertThrowsError(
        try store.add(ManualTransactionDraft(amountMinor: amount, descriptionText: "REFUSED"))
      ) { error in
        XCTAssertEqual(error as? AmountValidationError, AmountValidationError.outOfRange(amountMinor: amount))
      }
      XCTAssertTrue(try context.fetch(FetchDescriptor<Transaction>()).isEmpty, "amount \(amount) wrote a row")
    }
  }

  func testAddAcceptsTheSmallestAndTheLargestAmount() throws {
    let (store, context) = try makeStore()
    _ = try store.add(ManualTransactionDraft(amountMinor: 1, descriptionText: "ONE PAISA"))
    _ = try store.add(ManualTransactionDraft(amountMinor: 100_000_000_000, descriptionText: "MAXIMUM"))
    XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 2)
  }

  /// The guard runs before any field is written, so the refused edit changes nothing:
  /// not the amount, and not the description it was submitted with.
  func testEditorUpdateRefusesZeroAndLeavesTheRowUnchanged() throws {
    let (editor, context) = try makeEditor()
    let row = Transaction(
      date: fixedNow,
      descriptionText: "COFFEE",
      normalizedDescription: normalizeDescription("COFFEE"),
      amountMinor: 450,
      directionRaw: Direction.debit.rawValue,
      dedupeKey: "coffee"
    )
    context.insert(row)
    try context.save()
    let id = row.id

    XCTAssertThrowsError(
      try editor.update(id, amountMinor: 0, date: fixedNow, descriptionText: "CHANGED", note: "changed")
    ) { error in
      XCTAssertEqual(error as? AmountValidationError, AmountValidationError.outOfRange(amountMinor: 0))
    }

    let refetched = try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
    XCTAssertEqual(refetched.amountMinor, 450)
    XCTAssertEqual(refetched.descriptionText, "COFFEE")
    XCTAssertNil(refetched.note)
  }

  func testEditorUpdateRefusesOneAboveTheMaximum() throws {
    let (editor, context) = try makeEditor()
    let row = Transaction(
      date: fixedNow,
      descriptionText: "COFFEE",
      normalizedDescription: normalizeDescription("COFFEE"),
      amountMinor: 450,
      directionRaw: Direction.debit.rawValue,
      dedupeKey: "coffee"
    )
    context.insert(row)
    try context.save()
    let id = row.id

    XCTAssertThrowsError(
      try editor.update(id, amountMinor: 100_000_000_001, date: fixedNow, descriptionText: "COFFEE", note: nil)
    )

    let refetched = try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
    XCTAssertEqual(refetched.amountMinor, 450)
  }

  /// Shaun's R8 amendment. An imported row can hold an amount above the bound. A
  /// date-only edit re-sends that stored amount unchanged and must be accepted, while
  /// the same row given a different out-of-range amount is still refused.
  func testEditorKeepsAnUnchangedOutOfRangeAmount() throws {
    let (editor, context) = try makeEditor()
    let stored = 100_000_000_001
    let row = Transaction(
      date: fixedNow,
      descriptionText: "IMPORTED",
      normalizedDescription: normalizeDescription("IMPORTED"),
      amountMinor: stored,
      directionRaw: Direction.debit.rawValue,
      dedupeKey: "imported"
    )
    context.insert(row)
    try context.save()
    let id = row.id
    let newDate = fixedNow.addingTimeInterval(86_400)

    try editor.update(id, amountMinor: stored, date: newDate, descriptionText: "IMPORTED", note: nil)

    let refetched = try XCTUnwrap(
      context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
    XCTAssertEqual(refetched.amountMinor, stored)
    XCTAssertEqual(refetched.date, newDate, "the date-only edit is written")

    XCTAssertThrowsError(
      try editor.update(id, amountMinor: stored + 1, date: newDate, descriptionText: "IMPORTED", note: nil)
    )
  }
}
