import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// B9, Andrews ruling 2026-11-16. Deleting one leg of a transfer unpairs its partner in the
/// same save: the partner loses its group id and its source, becomes an ordinary row, and
/// counts in the period totals again. A row that is not a transfer leg deletes exactly as before.
///
/// XCTest on an `InMemoryStack` held in a property for the life of the test. A `ModelContext`
/// does not keep its container alive (the container-lifetime trap).
@MainActor
final class TransferDeleteUnpairTests: XCTestCase {
  private var stacks: [InMemoryStack] = []
  private let calendar = NomiCalendar.india
  private let stamp = Date(timeIntervalSince1970: 1_700_000_000)
  private let later = Date(timeIntervalSince1970: 1_700_500_000)
  private let period = InsightPeriod.month(year: 2026, month: 11)

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
  }

  private struct Fixture {
    let transactions: SwiftDataTransactionStore
    let insights: SwiftDataInsightsStore
    let context: ModelContext
    /// The store's clock. Every write reads it; a test moves it to `later` just before a delete.
    let clock: Clock
  }

  /// One container, one cache shared by the writer and the reader, so `didWrite` is what the
  /// reader sees. The clock starts at `stamp` for the setup writes.
  private func makeFixture(
    observer: (any PostCommitObserver)? = nil,
    saveDeleteUnpairWrite: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let cache = InsightsCache()
    let coordinator = WriteCoordinator(cache: cache)
    if let observer { coordinator.setObserver(observer) }
    let clock = Clock(now: stamp)
    let transactions = SwiftDataTransactionStore(
      context: stack.context,
      coordinator: coordinator,
      calendar: calendar,
      now: { clock.now },
      saveDeleteUnpairWrite: saveDeleteUnpairWrite
    )
    return Fixture(
      transactions: transactions,
      insights: SwiftDataInsightsStore(context: stack.context, cache: cache),
      context: stack.context,
      clock: clock
    )
  }

  private func row(_ context: ModelContext, _ id: UUID) throws -> Transaction? {
    let target = id
    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.id == target })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  // MARK: - Totals

  /// The debit leg is deleted. The credit leg was excluded as a transfer leg; now it is an
  /// ordinary row and the November income total includes it.
  func testDeletingTheDebitLegLetsTheCreditLegCountAsIncome() throws {
    let f = try makeFixture()
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 30_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    let debitID = debit.id
    let creditID = credit.id

    let before = try f.insights.insights(for: period)
    XCTAssertEqual(before.debitMinor, 0, "a transfer leg counted as spend before the delete")
    XCTAssertEqual(before.creditMinor, 0, "a transfer leg counted as income before the delete")

    f.clock.now = later

    try f.transactions.delete(debitID)

    let gone = try row(f.context, debitID)
    XCTAssertNil(gone, "the deleted leg is still stored")
    let partner = try XCTUnwrap(try row(f.context, creditID))
    XCTAssertNil(partner.transferGroupID, "the partner is still grouped")
    XCTAssertNil(partner.transferSourceRaw, "the partner still carries a transfer source")
    XCTAssertFalse(partner.isTransfer, "the partner is still a transfer leg")
    XCTAssertEqual(partner.amountMinor, 30_000)
    XCTAssertEqual(partner.updatedAt, later, "the partner's change is not stamped")

    let after = try f.insights.insights(for: period)
    XCTAssertEqual(after.creditMinor, 30_000, "the orphaned credit leg does not count again")
    XCTAssertEqual(after.debitMinor, 0)
    XCTAssertEqual(after.netMinor, 30_000)
  }

  /// The mirror: the credit leg is deleted and the debit leg counts as spend.
  func testDeletingTheCreditLegLetsTheDebitLegCountAsSpend() throws {
    let f = try makeFixture()
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 30_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    let debitID = debit.id
    let creditID = credit.id

    let before = try f.insights.insights(for: period)
    XCTAssertEqual(before.debitMinor, 0)
    XCTAssertEqual(before.creditMinor, 0)

    f.clock.now = later

    try f.transactions.delete(creditID)

    let gone = try row(f.context, creditID)
    XCTAssertNil(gone, "the deleted leg is still stored")
    let partner = try XCTUnwrap(try row(f.context, debitID))
    XCTAssertNil(partner.transferGroupID, "the partner is still grouped")
    XCTAssertNil(partner.transferSourceRaw, "the partner still carries a transfer source")
    XCTAssertFalse(partner.isTransfer, "the partner is still a transfer leg")

    let after = try f.insights.insights(for: period)
    XCTAssertEqual(after.debitMinor, 30_000, "the orphaned debit leg does not count again")
    XCTAssertEqual(after.creditMinor, 0)
    XCTAssertEqual(after.netMinor, -30_000)
  }

  // MARK: - Reporting

  /// `didWrite` carries the categories of both legs, not only the deleted one: the partner's
  /// total moved too, because it now counts.
  func testTheDeleteReportsBothLegsCategoriesToDidWrite() async throws {
    let food = UUID()
    let bills = UUID()
    let recorder = UnpairWriteRecorder()
    let f = try makeFixture(observer: recorder)
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 30_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    let debitID = debit.id
    debit.categoryID = food
    credit.categoryID = bills
    try f.context.save()

    f.clock.now = later

    try f.transactions.delete(debitID)

    await fulfillment(of: [recorder.received], timeout: 2)
    XCTAssertEqual(
      recorder.calls, [[food, bills]],
      "the delete did not report both legs' categories; got \(recorder.calls)")
  }

  // MARK: - Partner already gone

  /// A group whose other leg is no longer stored. The delete still succeeds, and nothing
  /// else in the store changes.
  func testAGroupWhosePartnerIsAlreadyGoneDeletesWithNothingElseChanged() throws {
    let f = try makeFixture()
    let orphanID = UUID()
    let orphan = Transaction(
      id: orphanID,
      date: day,
      descriptionText: "Transfer",
      normalizedDescription: "transfer",
      amountMinor: 30_000,
      directionRaw: Direction.debit.rawValue,
      accountID: UUID(),
      updatedAt: stamp,
      transferGroupID: TransferGroupID.make(single: orphanID),
      transferSourceRaw: TransferSource.manual.rawValue
    )
    f.context.insert(orphan)
    let bystander = try f.transactions.add(
      ManualTransactionDraft(
        date: day, amountMinor: 20_000, descriptionText: "SWIGGY", accountID: UUID()))
    let bystanderID = bystander.id
    try f.context.save()
    let bystanderBefore = try RowState(try XCTUnwrap(try row(f.context, bystanderID)))

    f.clock.now = later

    try f.transactions.delete(orphanID)

    let gone = try row(f.context, orphanID)
    XCTAssertNil(gone, "the orphan is still stored")
    let bystanderAfter = try RowState(try XCTUnwrap(try row(f.context, bystanderID)))
    XCTAssertEqual(bystanderAfter, bystanderBefore, "an unrelated row changed")
    let total = try f.context.fetchCount(FetchDescriptor<Transaction>())
    XCTAssertEqual(total, 1, "the delete removed or added something besides the orphan")
  }

  // MARK: - Rollback

  /// The one save fails. Neither the delete nor the partner's unpairing persists: the leg is
  /// still stored and still paired, the totals are the ones from before, and the context holds
  /// no change for a later save to flush.
  func testAFailedSaveRollsBothChangesBack() throws {
    let f = try makeFixture(saveDeleteUnpairWrite: { _ in throw DeleteForcedSaveFailure() })
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 30_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    let debitID = debit.id
    let creditID = credit.id
    let creditBefore = try RowState(try XCTUnwrap(try row(f.context, creditID)))
    let totalsBefore = try f.insights.insights(for: period)

    f.clock.now = later
    XCTAssertThrowsError(try f.transactions.delete(debitID))

    let debitStill = try row(f.context, debitID)
    XCTAssertNotNil(debitStill, "the delete persisted through a failed save")
    XCTAssertEqual(
      try RowState(try XCTUnwrap(try row(f.context, creditID))), creditBefore,
      "the partner's unpairing persisted through a failed save")
    XCTAssertFalse(f.context.hasChanges, "a failed save left changes in the context")
    let totalsAfter = try f.insights.insights(for: period)
    XCTAssertEqual(totalsAfter.debitMinor, totalsBefore.debitMinor)
    XCTAssertEqual(totalsAfter.creditMinor, totalsBefore.creditMinor)
  }

  // MARK: - Non-transfer delete

  /// A row that is not a transfer leg deletes exactly as it did before B9. The other ordinary
  /// rows and an unrelated transfer pair keep every field they had.
  func testANonTransferDeleteTouchesOnlyThatRow() throws {
    let f = try makeFixture()
    let doomed = try f.transactions.add(
      ManualTransactionDraft(
        date: day, amountMinor: 10_000, descriptionText: "CHAI", accountID: UUID()))
    let keep = try f.transactions.add(
      ManualTransactionDraft(
        date: day, amountMinor: 20_000, descriptionText: "SWIGGY", accountID: UUID()))
    let (debit, credit) = try f.transactions.addTransfer(
      amountMinor: 50_000, date: day, fromAccountID: UUID(), toAccountID: UUID(), note: nil)
    let doomedID = doomed.id
    let keepID = keep.id
    let debitID = debit.id
    let creditID = credit.id

    let keepBefore = try RowState(try XCTUnwrap(try row(f.context, keepID)))
    let debitBefore = try RowState(try XCTUnwrap(try row(f.context, debitID)))
    let creditBefore = try RowState(try XCTUnwrap(try row(f.context, creditID)))

    f.clock.now = later

    try f.transactions.delete(doomedID)

    let gone = try row(f.context, doomedID)
    XCTAssertNil(gone, "the deleted row is still stored")
    let keepAfter = try RowState(try XCTUnwrap(try row(f.context, keepID)))
    let debitAfter = try RowState(try XCTUnwrap(try row(f.context, debitID)))
    let creditAfter = try RowState(try XCTUnwrap(try row(f.context, creditID)))
    XCTAssertEqual(keepAfter, keepBefore, "an ordinary row changed")
    XCTAssertEqual(debitAfter, debitBefore, "the unrelated pair's debit leg changed")
    XCTAssertEqual(creditAfter, creditBefore, "the unrelated pair's credit leg changed")
  }
}

/// A save the test refuses on purpose. Private to this file.
private struct DeleteForcedSaveFailure: Error {}

/// Every field of a row the delete must leave alone. A value, so a before and after compare.
private struct RowState: Equatable {
  let id: UUID
  let amountMinor: Int
  let categoryID: UUID?
  let categorySourceRaw: String
  let accountID: UUID?
  let transferGroupID: UUID?
  let transferSourceRaw: String?
  let updatedAt: Date

  init(_ row: Transaction) {
    id = row.id
    amountMinor = row.amountMinor
    categoryID = row.categoryID
    categorySourceRaw = row.categorySourceRaw
    accountID = row.accountID
    transferGroupID = row.transferGroupID
    transferSourceRaw = row.transferSourceRaw
    updatedAt = row.updatedAt
  }
}

/// The fixture's clock. A class, so the store's closure reads the value the test sets later.
private final class Clock {
  var now: Date

  init(now: Date) {
    self.now = now
  }
}

/// Records each category set the coordinator hands the observer. The calls are dispatched in a
/// `Task`, so the test waits for the first one.
private final class UnpairWriteRecorder: PostCommitObserver, @unchecked Sendable {
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
