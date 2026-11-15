import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// B2, I-11. A manual transfer is two legs written in one save. It moves the two
/// account balances and leaves the period's spent and income totals where they were.
///
/// XCTest on an `InMemoryStack` held in a property for the life of the test. A
/// `ModelContext` does not keep its container alive (the container-lifetime trap).
@MainActor
final class ManualTransferTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india
  private let stamp = Date(timeIntervalSince1970: 1_700_000_000)

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private struct Fixture {
    let transactions: SwiftDataTransactionStore
    let accounts: SwiftDataAccountStore
    let insights: SwiftDataInsightsStore
    let context: ModelContext
  }

  /// One container, one cache shared by the writer and the readers. A second cache would
  /// make `didWrite` invisible to the reader and every assertion here would be about nothing.
  private func makeFixture(
    saveTransferWrite: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    let fixedNow = stamp
    let transactions = SwiftDataTransactionStore(
      context: stack.context,
      coordinator: coordinator,
      calendar: calendar,
      now: { fixedNow },
      saveTransferWrite: saveTransferWrite
    )
    return Fixture(
      transactions: transactions,
      accounts: SwiftDataAccountStore(context: stack.context, coordinator: coordinator),
      insights: SwiftDataInsightsStore(context: stack.context, cache: cache),
      context: stack.context
    )
  }

  private func allRows(_ context: ModelContext) throws -> [Transaction] {
    try context.fetch(FetchDescriptor<Transaction>())
  }

  // MARK: - The legs

  /// The table from the plan, `amount | from | to → debit leg on from, credit leg on to,
  /// one group id, both transferSource manual`. Two more facts are checked on every row: the
  /// note lands on both legs trimmed, and no leg carries a category or needs review.
  func testEachTransferWritesTwoLegsWithTheSpecifiedFields() throws {
    let f = try makeFixture()
    let from = UUID()
    let to = UUID()
    let rows: [(amount: Int, from: UUID, to: UUID)] = [
      (1, from, to),
      (50_000, to, from),
      (AmountRules.maximumMinor, from, to),
    ]
    var groups: [UUID] = []

    for row in rows {
      let (debit, credit) = try f.transactions.addTransfer(
        amountMinor: row.amount, date: day, fromAccountID: row.from, toAccountID: row.to, note: "  Rent  ")

      XCTAssertNotEqual(debit.id, credit.id)
      XCTAssertEqual(debit.direction, .debit)
      XCTAssertEqual(credit.direction, .credit)
      XCTAssertEqual(debit.accountID, row.from, "the debit leg is not on the from account")
      XCTAssertEqual(credit.accountID, row.to, "the credit leg is not on the to account")
      XCTAssertEqual(debit.amountMinor, row.amount)
      XCTAssertEqual(credit.amountMinor, row.amount)
      XCTAssertEqual(debit.date, credit.date)

      let group = try XCTUnwrap(debit.transferGroupID)
      XCTAssertEqual(credit.transferGroupID, group, "the two legs do not share one group id")
      XCTAssertFalse(groups.contains(group), "two transfers share a group id")
      groups.append(group)

      XCTAssertEqual(debit.transferSource, TransferSource.manual)
      XCTAssertEqual(credit.transferSource, TransferSource.manual)
      XCTAssertNil(debit.categoryID)
      XCTAssertNil(credit.categoryID)
      XCTAssertFalse(debit.needsReview)
      XCTAssertFalse(credit.needsReview)
      XCTAssertEqual(debit.sourceRaw, IngestSource.manual.rawValue)
      XCTAssertEqual(credit.sourceRaw, IngestSource.manual.rawValue)
      XCTAssertEqual(debit.descriptionText, "Transfer")
      XCTAssertEqual(credit.descriptionText, "Transfer")
      XCTAssertEqual(debit.note, "Rent", "the trimmed note is not on the debit leg")
      XCTAssertEqual(credit.note, "Rent", "the trimmed note is not on the credit leg")
    }

    XCTAssertEqual(try allRows(f.context).count, rows.count * 2, "a transfer did not write exactly two rows")
    XCTAssertFalse(f.context.hasChanges)
  }

  func testTheTwoLegsGetDistinctDedupeKeysBecauseDirectionIsPartOfTheKey() throws {
    let f = try makeFixture()
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)

    let normalized = normalizeDescription("Transfer")
    XCTAssertEqual(
      debit.dedupeKey,
      makeDedupeKey(date: day, amountMinor: 50_000, directionRaw: "debit", normalizedDescription: normalized, calendar: calendar))
    XCTAssertEqual(
      credit.dedupeKey,
      makeDedupeKey(date: day, amountMinor: 50_000, directionRaw: "credit", normalizedDescription: normalized, calendar: calendar))
    XCTAssertNotEqual(debit.dedupeKey, credit.dedupeKey)
  }

  /// I-11 Amendment 1. The group is derived from the two leg ids, so it is the same however the pair
  /// is read back: it is `TransferGroupID.make` over the debit and credit ids, in either order.
  func testTransferGroupIsDeterministic() throws {
    let f = try makeFixture()
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)

    let group = try XCTUnwrap(debit.transferGroupID)
    XCTAssertEqual(group, TransferGroupID.make(debit.id, credit.id))
    XCTAssertEqual(group, TransferGroupID.make(credit.id, debit.id))
  }

  // MARK: - Refusals

  func testFromAndToTheSameAccountIsRefusedAndNothingIsWritten() throws {
    let f = try makeFixture()
    let account = UUID()

    XCTAssertThrowsError(
      try f.transactions.addTransfer(
        amountMinor: 50_000, date: day, fromAccountID: account, toAccountID: account, note: nil)
    ) { error in
      XCTAssertEqual(error as? TransactionStoreError, .sameAccount)
    }
    XCTAssertEqual(try allRows(f.context).count, 0)
  }

  /// R8. Zero and one above the bound are refused before anything is written.
  func testAnAmountOutsideTheBoundsIsRefusedAndNothingIsWritten() throws {
    let f = try makeFixture()
    let from = UUID()
    let to = UUID()

    for amount in [0, AmountRules.maximumMinor + 1] {
      XCTAssertThrowsError(
        try f.transactions.addTransfer(
          amountMinor: amount, date: day, fromAccountID: from, toAccountID: to, note: nil)
      ) { error in
        XCTAssertEqual(error as? AmountValidationError, .outOfRange(amountMinor: amount))
      }
    }
    XCTAssertEqual(try allRows(f.context).count, 0)
  }

  /// One save for both legs. A save that fails leaves neither leg, and nothing is dirty for a
  /// later save to flush.
  func testAFailedSaveWritesNeitherLeg() throws {
    let gate = TransferSaveGate()
    let f = try makeFixture { context in
      if gate.refuses { throw TransferForcedSaveFailure() }
      try context.save()
    }
    gate.refuses = true

    XCTAssertThrowsError(
      try f.transactions.addTransfer(
        amountMinor: 50_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    ) { error in
      XCTAssertTrue(error is TransferForcedSaveFailure)
    }
    XCTAssertEqual(try allRows(f.context).count, 0, "a failed transfer left a leg behind")
    XCTAssertFalse(f.context.hasChanges, "a failed transfer left changes for a later save to flush")
  }

  // MARK: - Money

  /// Hand computed. Account A opens at ₹1,000 (100_000 paise). A manual ₹200 debit (20_000)
  /// lands on it in November. Then a ₹300 transfer (30_000) moves from A to B, which opens empty.
  ///
  /// Balances (opening + credit − debit, per `trackedBalanceMinor`):
  ///   A: 100_000 − 20_000 = 80_000 before; 100_000 − 20_000 − 30_000 = 50_000 after.
  ///   B: 0 before; 0 + 30_000 = 30_000 after.
  /// November, spent and income (`isCountedSpend` excludes transfer legs):
  ///   debit 20_000 and credit 0, both before and after; net −20_000 both times.
  func testATransferMovesTheTwoBalancesAndNoPeriodTotal() throws {
    let f = try makeFixture()
    let a = try f.accounts.create(
      displayName: "HDFC 4471", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank",
      openingBalanceMinor: 100_000)
    let b = try f.accounts.create(
      displayName: "ICICI 9020", institution: "ICICI Bank", lastFour: "9020", kindRaw: "bank",
      openingBalanceMinor: nil)
    _ = try f.transactions.add(
      ManualTransactionDraft(date: day, amountMinor: 20_000, descriptionText: "SWIGGY", accountID: a.id))

    let period = InsightPeriod.month(year: 2026, month: 11)
    let spentBefore = try f.insights.insights(for: period)
    let balancesBefore = try balances(f.insights)
    XCTAssertEqual(balancesBefore[a.id], 80_000)
    XCTAssertEqual(balancesBefore[b.id], 0)

    _ = try f.transactions.addTransfer(
      amountMinor: 30_000, date: day, fromAccountID: a.id, toAccountID: b.id, note: nil)

    let spentAfter = try f.insights.insights(for: period)
    let balancesAfter = try balances(f.insights)
    XCTAssertEqual(balancesAfter[a.id], 50_000)
    XCTAssertEqual(balancesAfter[b.id], 30_000)

    XCTAssertEqual(spentAfter.debitMinor, spentBefore.debitMinor, "a transfer changed spent")
    XCTAssertEqual(spentAfter.creditMinor, spentBefore.creditMinor, "a transfer changed income")
    XCTAssertEqual(spentAfter.netMinor, spentBefore.netMinor)
    XCTAssertEqual(spentAfter.debitMinor, 20_000)
    XCTAssertEqual(spentAfter.creditMinor, 0)
  }

  // MARK: - The manual note

  /// I-11 step 1. `add` stores the note trimmed, and a note that is empty after trimming is nil.
  func testAManualAddStoresTheTrimmedNoteAndABlankNoteIsNil() throws {
    let f = try makeFixture()
    let kept = try f.transactions.add(
      ManualTransactionDraft(date: day, amountMinor: 500, descriptionText: "CHAI", note: "  for Ravi  "))
    let blank = try f.transactions.add(
      ManualTransactionDraft(date: day, amountMinor: 600, descriptionText: "CHAI", note: "   "))
    let none = try f.transactions.add(
      ManualTransactionDraft(date: day, amountMinor: 700, descriptionText: "CHAI"))

    XCTAssertEqual(kept.note, "for Ravi")
    XCTAssertNil(blank.note)
    XCTAssertNil(none.note)
  }

  // MARK: - Helpers

  private func balances(_ insights: SwiftDataInsightsStore) throws -> [UUID: Int] {
    Dictionary(
      uniqueKeysWithValues: try insights.accountSummaries(includeArchived: false).map {
        ($0.id, $0.trackedBalanceMinor)
      })
  }
}

/// A save the test refuses on purpose. Private to this file.
private struct TransferForcedSaveFailure: Error {}

/// The switch for the transfer's one save. A class, so the closure and the test share the flag.
private final class TransferSaveGate {
  var refuses = false
}
