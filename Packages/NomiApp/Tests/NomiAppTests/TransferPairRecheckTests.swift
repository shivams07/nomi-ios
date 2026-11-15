import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// R8, step 7. An amount or date edit that breaks a transfer pair unpairs both legs
/// to `(nil, nil)`. XCTest, not swift-testing: a `ModelContainer` traps under the
/// swift-testing runner. Containers are held in a stored property (see
/// `InMemoryStack`).
@MainActor
final class TransferPairRecheckTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india
  private let savingsAccount = UUID()
  private let cardAccount = UUID()

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private func plusDays(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: days, to: day)!
  }

  private func makeEditor() throws -> (SwiftDataTransactionEditor, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let editor = SwiftDataTransactionEditor(
      context: stack.context,
      coordinator: WriteCoordinator(cache: InsightsCache()),
      now: { Date(timeIntervalSince1970: 1_700_000_000) },
      calendar: calendar
    )
    return (editor, stack.context)
  }

  /// An auto-matched pair: ₹500 debit from savings, ₹500 credit to the card, the
  /// same day.
  private func makeAutoPair(_ context: ModelContext) throws -> (debit: Transaction, credit: Transaction) {
    let debit = Transaction(
      date: day,
      descriptionText: "NEFT TO CARD",
      normalizedDescription: normalizeDescription("NEFT TO CARD"),
      amountMinor: 50_000,
      directionRaw: Direction.debit.rawValue,
      accountID: savingsAccount,
      dedupeKey: "debit"
    )
    let credit = Transaction(
      date: day,
      descriptionText: "NEFT FROM SAVINGS",
      normalizedDescription: normalizeDescription("NEFT FROM SAVINGS"),
      amountMinor: 50_000,
      directionRaw: Direction.credit.rawValue,
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

  func testAmountEditThatBreaksTheMatchUnpairsBothLegs() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)

    try editor.update(debit.id, amountMinor: 50_100, date: day, descriptionText: "NEFT TO CARD", note: nil)

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertEqual(d.amountMinor, 50_100)
    XCTAssertNil(d.transferGroupID)
    XCTAssertNil(d.transferSourceRaw)
    XCTAssertNil(c.transferGroupID, "the partner is unpaired too")
    XCTAssertNil(c.transferSourceRaw)
  }

  func testDateEditWithinTheWindowKeepsThePair() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)
    let group = TransferGroupID.make(debit.id, credit.id)

    try editor.update(debit.id, amountMinor: 50_000, date: plusDays(2), descriptionText: "NEFT TO CARD", note: nil)

    let d = try fetchRow(context, debit.id)
    let c = try fetchRow(context, credit.id)
    XCTAssertEqual(d.transferGroupID, group, "two days apart still matches")
    XCTAssertEqual(c.transferGroupID, group)
    XCTAssertEqual(d.transferSourceRaw, TransferSource.auto.rawValue)
    XCTAssertEqual(c.transferSourceRaw, TransferSource.auto.rawValue)
  }

  /// Four days apart is outside the three-day window: the pair breaks.
  func testDateEditOutsideTheWindowUnpairsBothLegs() throws {
    let (editor, context) = try makeEditor()
    let (debit, credit) = try makeAutoPair(context)

    try editor.update(debit.id, amountMinor: 50_000, date: plusDays(4), descriptionText: "NEFT TO CARD", note: nil)

    XCTAssertNil(try fetchRow(context, debit.id).transferGroupID)
    XCTAssertNil(try fetchRow(context, credit.id).transferGroupID)
  }

  /// A solo manual mark has no partner to judge, so an edit leaves it alone.
  func testEditOfASoloManualRowLeavesItsMarkUnchanged() throws {
    let (editor, context) = try makeEditor()
    let row = Transaction(
      date: day,
      descriptionText: "CASH TRANSFER",
      normalizedDescription: normalizeDescription("CASH TRANSFER"),
      amountMinor: 50_000,
      directionRaw: Direction.debit.rawValue,
      accountID: savingsAccount,
      dedupeKey: "solo"
    )
    let solo = TransferGroupID.make(single: row.id)
    row.transferGroupID = solo
    row.transferSource = .manual
    context.insert(row)
    try context.save()

    try editor.update(row.id, amountMinor: 99_900, date: day, descriptionText: "CASH TRANSFER", note: nil)

    let refetched = try fetchRow(context, row.id)
    XCTAssertEqual(refetched.amountMinor, 99_900)
    XCTAssertEqual(refetched.transferGroupID, solo)
    XCTAssertEqual(refetched.transferSourceRaw, TransferSource.manual.rawValue)
  }
}
