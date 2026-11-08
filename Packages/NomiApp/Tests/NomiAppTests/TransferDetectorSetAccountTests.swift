import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// DEC-05 detector, the `setAccount` half (TR2, TR5). Assigning the card to a
/// credit row can complete a pair, and the pair is written whole or not at all.
///
/// XCTest on a real container. The container is a stored property: a helper that
/// returns only `mainContext` lets the container go while the context is still
/// in use, which traps in SwiftData (memory: Xcode XCTest SwiftData trap).
@MainActor
final class TransferDetectorSetAccountTests: XCTestCase {

  private var keepAlive: ModelContainer?
  /// Makes the one save `setAccount` makes fail while `refuses` is true (TR4 rollback).
  private let saveGate = SaveGate()

  private let savings = UUID(uuidString: "AC000000-0000-0000-0000-00000000000A")!
  private let card = UUID(uuidString: "AC000000-0000-0000-0000-00000000000C")!
  private let s = UUID(uuidString: "5A000000-0000-0000-0000-000000000001")!
  private let c = UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
  private let s2 = UUID(uuidString: "5A000000-0000-0000-0000-000000000004")!
  /// Python: `make_pair(S, C)` = `68b3c33e-3c4f-86e1-26f9-fa94a30c05b4`.
  private let pairGroupSC = UUID(uuidString: "68B3C33E-3C4F-86E1-26F9-FA94A30C05B4")!

  /// Asia/Kolkata, as the device calendar stands in for the tests (TR2).
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  private let commitTime = Date(timeIntervalSince1970: 1_790_000_000)

  // MARK: - Setup

  private func makeStore() throws -> (SwiftDataTransactionStore, ModelContext, WriteCoordinator) {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    keepAlive = container
    let context = container.mainContext
    context.insert(Account(id: savings, displayName: "Savings", institution: "HDFC", lastFour: "2210", kindRaw: "bank"))
    context.insert(Account(id: card, displayName: "Card", institution: "HDFC", lastFour: "4471", kindRaw: "card"))
    let coordinator = WriteCoordinator(cache: InsightsCache())
    let gate = saveGate
    let store = SwiftDataTransactionStore(
      context: context,
      coordinator: coordinator,
      transferCalendar: calendar,
      now: { self.commitTime },
      saveAccountWrite: { context in
        if gate.refuses { throw ForcedSaveFailure() }
        try context.save()
      })
    return (store, context, coordinator)
  }

  /// An email row from a card alert, the kind `setAccount` learns a binding from.
  private func emailRow(_ id: UUID, account: UUID?) -> Transaction {
    Transaction(
      id: id,
      date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!,
      descriptionText: "HDFC CARD ALERT",
      normalizedDescription: "HDFC CARD ALERT",
      amountMinor: 75_000,
      directionRaw: Direction.debit.rawValue,
      categorySourceRaw: CategorySource.none.rawValue,
      accountID: account,
      sourceRaw: IngestSource.email.rawValue,
      dedupeKey: id.uuidString,
      createdAt: commitTime,
      updatedAt: commitTime,
      senderDomain: "hdfcbank.net",
      cardFragment: "4471"
    )
  }

  private func row(
    _ id: UUID,
    _ direction: Direction,
    _ narration: String,
    day: Int,
    account: UUID?,
    categoryID: UUID? = nil,
    groupID: UUID? = nil,
    sourceRaw: String? = nil,
    amount: Int = 2_000_000
  ) -> Transaction {
    Transaction(
      id: id,
      date: calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!,
      descriptionText: narration,
      normalizedDescription: narration.uppercased(),
      amountMinor: amount,
      directionRaw: direction.rawValue,
      categoryID: categoryID,
      categorySourceRaw: categoryID == nil ? CategorySource.none.rawValue : CategorySource.manual.rawValue,
      accountID: account,
      sourceRaw: IngestSource.manual.rawValue,
      dedupeKey: id.uuidString,
      createdAt: commitTime,
      updatedAt: commitTime,
      transferGroupID: groupID,
      transferSourceRaw: sourceRaw
    )
  }

  private func rows(_ context: ModelContext) throws -> [UUID: Transaction] {
    Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Transaction>()).map { ($0.id, $0) })
  }

  // MARK: - Tests

  /// Assigning the card to the credit completes fixture F: both legs take the
  /// pair's group and `auto`.
  func testAssigningTheCardMarksThePair() throws {
    let (store, context, _) = try makeStore()
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil))
    try context.save()

    try store.setAccount(c, to: card)

    let rows = try rows(context)
    XCTAssertEqual(rows[s]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[s]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[c]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[c]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[c]?.accountID, card)
  }

  /// Unassigning marks nothing and clears nothing: a pair already written stays.
  func testUnassigningMarksNothing() throws {
    let (store, context, _) = try makeStore()
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings,
                       groupID: pairGroupSC, sourceRaw: "auto"))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: card,
                       groupID: pairGroupSC, sourceRaw: "auto"))
    try context.save()

    try store.setAccount(c, to: nil)

    let rows = try rows(context)
    XCTAssertNil(rows[c]?.accountID)
    XCTAssertEqual(rows[s]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[s]?.transferSourceRaw, "auto")
    XCTAssertEqual(rows[c]?.transferGroupID, pairGroupSC)
    XCTAssertEqual(rows[c]?.transferSourceRaw, "auto")
  }

  /// Two savings debits of the same amount in the window make the credit
  /// ambiguous once the card is assigned. Nothing is marked.
  func testAnAmbiguousMatchAfterAssignmentMarksNothing() throws {
    let (store, context, _) = try makeStore()
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 9, account: savings))
    context.insert(row(s2, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil))
    try context.save()

    try store.setAccount(c, to: card)

    let rows = try rows(context)
    XCTAssertNil(rows[s]?.transferSourceRaw)
    XCTAssertNil(rows[s2]?.transferSourceRaw)
    XCTAssertNil(rows[c]?.transferSourceRaw)
    XCTAssertNil(rows[c]?.transferGroupID)
  }

  /// A debit the user said is not a transfer is never claimed, and it does not
  /// count as a candidate either: the credit has no partner.
  func testADecidedPartnerIsNotClaimed() throws {
    let (store, context, _) = try makeStore()
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings,
                       sourceRaw: TransferSource.rejected.rawValue))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil))
    try context.save()

    try store.setAccount(c, to: card)

    let rows = try rows(context)
    XCTAssertNil(rows[s]?.transferGroupID)
    XCTAssertEqual(rows[s]?.transferSourceRaw, TransferSource.rejected.rawValue)
    XCTAssertNil(rows[c]?.transferGroupID)
    XCTAssertNil(rows[c]?.transferSourceRaw)
  }

  /// The write reports the categories of the legs it marked, so the observer
  /// hears both, through the coordinator's one notification.
  func testTheCoordinatorHearsTheMarkedCategories() async throws {
    let (store, context, coordinator) = try makeStore()
    let categoryS = UUID(uuidString: "CA000000-0000-0000-0000-000000000001")!
    let categoryC = UUID(uuidString: "CA000000-0000-0000-0000-000000000002")!
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings, categoryID: categoryS))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil, categoryID: categoryC))
    try context.save()
    let recorder = CategoryRecorder()
    coordinator.setObserver(recorder)

    try store.setAccount(c, to: card)

    await fulfillment(of: [recorder.received], timeout: 5)
    XCTAssertEqual(recorder.calls, [Set([categoryS, categoryC])])
  }

  // MARK: - Rollback (TR4)

  /// The save fails after the card is assigned and the pair is marked. Neither
  /// the assignment nor the marks are left dirty in the context, and nothing
  /// reaches the store.
  func testAFailedSaveRollsBackTheAccountAndTheMarks() throws {
    let (store, context, _) = try makeStore()
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil))
    try context.save()

    saveGate.refuses = true
    XCTAssertThrowsError(try store.setAccount(c, to: card)) { error in
      XCTAssertTrue(error is ForcedSaveFailure)
    }

    let inMemory = try rows(context)
    XCTAssertNil(inMemory[c]?.accountID, "the assignment must not stay dirty in the context")
    XCTAssertNil(inMemory[c]?.transferGroupID)
    XCTAssertNil(inMemory[c]?.transferSourceRaw)
    XCTAssertNil(inMemory[s]?.transferGroupID)
    XCTAssertNil(inMemory[s]?.transferSourceRaw)

    let stored = try rows(ModelContext(try XCTUnwrap(keepAlive)))
    XCTAssertNil(stored[c]?.accountID)
    XCTAssertNil(stored[s]?.transferSourceRaw)
    XCTAssertNil(stored[c]?.transferSourceRaw)
  }

  /// The defect the rollback prevents: a failed assignment left dirty in the
  /// context is flushed by the next save through the store. After the failure
  /// and a successful unrelated write, neither the card nor the marks persist.
  func testALaterSaveDoesNotFlushTheFailedAssignment() throws {
    let (store, context, _) = try makeStore()
    let other = UUID(uuidString: "0B000000-0000-0000-0000-000000000001")!
    let userCategory = UUID(uuidString: "CA000000-0000-0000-0000-0000000000AA")!
    context.insert(row(s, .debit, "HDFC CREDIT CARD PAYMENT", day: 10, account: savings))
    context.insert(row(c, .credit, "PAYMENT RECEIVED - THANK YOU", day: 11, account: nil))
    context.insert(row(other, .debit, "UNRELATED GROCERIES", day: 12, account: savings))
    try context.save()

    saveGate.refuses = true
    XCTAssertThrowsError(try store.setAccount(c, to: card))

    saveGate.refuses = false
    try store.setCategory(other, to: userCategory)

    let stored = try rows(ModelContext(try XCTUnwrap(keepAlive)))
    XCTAssertEqual(stored[other]?.categoryID, userCategory, "the later save did happen")
    XCTAssertNil(stored[c]?.accountID, "the failed assignment must not be flushed")
    XCTAssertNil(stored[s]?.transferSourceRaw)
    XCTAssertNil(stored[c]?.transferSourceRaw)
  }

  /// An email row's assignment also teaches a binding and applies to its
  /// unassigned siblings. A failed save reverts all of it, not only the marks.
  func testAFailedSaveRevertsTheLearnedBindingAndTheSiblings() throws {
    let (store, context, _) = try makeStore()
    let first = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    let sibling = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
    context.insert(emailRow(first, account: nil))
    context.insert(emailRow(sibling, account: nil))
    try context.save()

    saveGate.refuses = true
    XCTAssertThrowsError(try store.setAccount(first, to: card))

    XCTAssertTrue(
      try context.fetch(FetchDescriptor<AccountBinding>()).isEmpty,
      "the learned binding must be rolled back in the context")
    let inMemory = try rows(context)
    XCTAssertNil(inMemory[first]?.accountID)
    XCTAssertNil(inMemory[sibling]?.accountID, "the sibling must not keep the rolled-back account")

    let container = try XCTUnwrap(keepAlive)
    let freshContext = ModelContext(container)
    XCTAssertTrue(try freshContext.fetch(FetchDescriptor<AccountBinding>()).isEmpty)
    let stored = try rows(freshContext)
    XCTAssertNil(stored[first]?.accountID)
    XCTAssertNil(stored[sibling]?.accountID)
  }
}

/// A save the test refuses on purpose. Shared by the setAccount rollback tests.
private struct ForcedSaveFailure: Error {}

/// Holds the test's switch for the one save `setAccount` makes. A class so the
/// closure the store keeps and the test both see the same flag.
private final class SaveGate {
  var refuses = false
}

/// Records each category set the coordinator hands the observer. Calls are
/// dispatched in a `Task`, so the test waits for the first one.
private final class CategoryRecorder: PostCommitObserver, @unchecked Sendable {
  let received = XCTestExpectation(description: "observer receives the marked categories")
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
