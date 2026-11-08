import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// DEC-05 A-05 items 11 and 16 to 19, on the SwiftData side. The five optional
/// `TransactionSnapshot` fields survive every copy site. A pipeline write is
/// compare-and-set on the transfer pair (Amendment 3): a stale snapshot never
/// undoes a decision, never re-creates a cleared mark, never overwrites an
/// unrecognised pair, and a reconcile never collapses a group it cannot read.
///
/// XCTest, and it stays XCTest: a `ModelContainer` traps under swift-testing
/// (see `SwiftDataPipelineStoreTests`).
final class TransferFieldCopyTests: XCTestCase {

  private func makeContainer() throws -> ModelContainer {
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
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  /// A snapshot as a pipeline draft would hand it over. `read` is the pair the
  /// pipeline read from the store with it; `nil` means it was not read from the
  /// store, which is the case for every snapshot a draft creates.
  private func snapshot(
    id: UUID = UUID(),
    source: String = IngestSource.email.rawValue,
    transferGroupID: UUID? = nil,
    transferSourceRaw: String? = nil,
    read: TransferPair? = nil,
    mergedCount: Int = 1,
    key: String = "k"
  ) -> TransactionSnapshot {
    var value = TransactionSnapshot(
      id: id,
      date: epoch,
      descriptionText: "HDFC CREDIT CARD PAYMENT",
      normalizedDescription: "HDFC CREDIT CARD PAYMENT",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      sourceRaw: source,
      mergedCount: mergedCount,
      dedupeKey: key,
      createdAt: epoch,
      updatedAt: epoch,
      senderDomain: nil,
      cardFragment: nil,
      needsReviewReason: nil,
      transferGroupID: transferGroupID,
      transferSourceRaw: transferSourceRaw
    )
    value.transferPairAtRead = read
    return value
  }

  private func pair(_ groupID: UUID?, _ sourceRaw: String?) -> TransferPair {
    TransferPair(groupID: groupID, sourceRaw: sourceRaw)
  }

  /// Item 11. Every optional, set to a value, comes back unchanged through
  /// Transaction -> snapshot -> Transaction.
  func testAllFiveOptionalFieldsRoundTrip() {
    let group = TransferGroupID.make(single: UUID())
    let row = Transaction(
      date: epoch,
      descriptionText: "X",
      amountMinor: 100,
      dedupeKey: "k",
      senderDomain: "hdfcbank.net",
      cardFragment: "6411",
      needsReviewReasonRaw: NeedsReviewReason.heuristic.rawValue,
      transferGroupID: group,
      transferSourceRaw: TransferSource.manual.rawValue
    )

    let back = Transaction.make(from: TransactionSnapshot(row))

    XCTAssertEqual(back.senderDomain, "hdfcbank.net")
    XCTAssertEqual(back.cardFragment, "6411")
    XCTAssertEqual(back.needsReviewReasonRaw, NeedsReviewReason.heuristic.rawValue)
    XCTAssertEqual(back.transferGroupID, group)
    XCTAssertEqual(back.transferSourceRaw, TransferSource.manual.rawValue)
  }

  /// Item 16. A snapshot whose read pair no longer matches the row, or whose read
  /// pair is unmarked while the row is marked, leaves the row's decision alone.
  func testAStaleSnapshotNeverOverridesAUserDecision() {
    let group = TransferGroupID.make(single: UUID())

    let manual = Transaction(dedupeKey: "k", transferGroupID: group, transferSourceRaw: "manual")
    manual.apply(snapshot(transferGroupID: nil, transferSourceRaw: nil, read: pair(nil, nil)))
    XCTAssertEqual(manual.transferGroupID, group)
    XCTAssertEqual(manual.transferSourceRaw, "manual")

    let rejected = Transaction(dedupeKey: "k", transferGroupID: nil, transferSourceRaw: "rejected")
    rejected.apply(snapshot(transferGroupID: group, transferSourceRaw: "auto", read: pair(nil, nil)))
    XCTAssertNil(rejected.transferGroupID)
    XCTAssertEqual(rejected.transferSourceRaw, "rejected")

    let auto = Transaction(dedupeKey: "k", transferGroupID: group, transferSourceRaw: "auto")
    auto.apply(snapshot(transferGroupID: nil, transferSourceRaw: nil, read: pair(group, "auto")))
    XCTAssertEqual(auto.transferGroupID, group, "an unmarked incoming never erases an auto mark")
  }

  /// Item 16, the other half: an unmarked row takes an automatic mark, and both
  /// fields arrive together.
  func testApplyWritesAnAutoMarkOntoAnUnmarkedRow() {
    let group = TransferGroupID.make(single: UUID())
    let row = Transaction(dedupeKey: "k")
    row.apply(snapshot(transferGroupID: group, transferSourceRaw: "auto", read: pair(nil, nil)))
    XCTAssertEqual(row.transferGroupID, group)
    XCTAssertEqual(row.transferSourceRaw, "auto")
  }

  /// Amendment 3, rule C. A snapshot not read from the store fails closed: no
  /// transfer field is written, but the other fields still are.
  func testASnapshotNotReadFromTheStoreNeverWritesThePair() {
    let group = TransferGroupID.make(single: UUID())
    let row = Transaction(dedupeKey: "k")
    row.apply(snapshot(transferGroupID: group, transferSourceRaw: "auto", read: nil, mergedCount: 3))
    XCTAssertNil(row.transferGroupID)
    XCTAssertNil(row.transferSourceRaw)
    XCTAssertEqual(row.mergedCount, 3, "the rest of apply still runs")
  }

  /// Amendment 3, rule U2. An unrecognised pair is never overwritten, from either
  /// side of the pair, even by a read-consistent snapshot.
  func testApplyNeverOverwritesAnUnrecognizedPair() {
    let group = TransferGroupID.make(single: UUID())
    let withGroup = Transaction(dedupeKey: "k", transferGroupID: group, transferSourceRaw: "zzz")
    withGroup.apply(snapshot(transferGroupID: nil, transferSourceRaw: nil, read: pair(group, "zzz")))
    XCTAssertEqual(withGroup.transferGroupID, group)
    XCTAssertEqual(withGroup.transferSourceRaw, "zzz")

    let withoutGroup = Transaction(dedupeKey: "k", transferGroupID: nil, transferSourceRaw: "zzz")
    withoutGroup.apply(snapshot(transferGroupID: group, transferSourceRaw: "manual", read: pair(nil, "zzz")))
    XCTAssertNil(withoutGroup.transferGroupID)
    XCTAssertEqual(withoutGroup.transferSourceRaw, "zzz")
  }

  /// Item 17. A duplicate carrying the user's manual mark is folded away; the
  /// unmarked survivor takes the mark.
  func testCollapseCarriesADuplicatesManualMarkToTheSurvivor() {
    let group = TransferGroupID.make(single: UUID())
    let earlier = snapshot(key: "same")
    var later = snapshot(key: "same")
    later.createdAt = epoch.addingTimeInterval(60)
    later.transferGroupID = group
    later.transferSourceRaw = "manual"

    let collapsed = MergeResolution.collapsing([later, earlier], now: epoch)

    XCTAssertEqual(collapsed?.survivor.id, earlier.id)
    XCTAssertEqual(collapsed?.survivor.transferGroupID, group)
    XCTAssertEqual(collapsed?.survivor.transferSourceRaw, "manual")
  }

  /// Amendment 3, rule U3, at the collapse. A group with an unrecognised pair on
  /// either side collapses to nothing: the same answer as two manual rows.
  func testCollapsingLeavesAGroupWithAnUnrecognizedPairAlone() {
    let group = TransferGroupID.make(single: UUID())
    let earlierUnrecognized = snapshot(transferGroupID: nil, transferSourceRaw: "zzz", key: "same")
    var laterManual = snapshot(transferGroupID: group, transferSourceRaw: "manual", key: "same")
    laterManual.createdAt = epoch.addingTimeInterval(60)
    XCTAssertNil(MergeResolution.collapsing([earlierUnrecognized, laterManual], now: epoch))

    let earlierPlain = snapshot(key: "same")
    var laterUnrecognized = snapshot(transferGroupID: group, transferSourceRaw: "zzz", key: "same")
    laterUnrecognized.createdAt = epoch.addingTimeInterval(60)
    XCTAssertNil(MergeResolution.collapsing([earlierPlain, laterUnrecognized], now: epoch))
  }

  /// Amendment 3, item 19 precondition. The store records the pair it read, so
  /// that a later write can be judged against it.
  func testTheStoreRecordsThePairItRead() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let group = TransferGroupID.make(single: UUID())
    try await store.apply(CommitPlan(inserts: [snapshot(transferGroupID: group, transferSourceRaw: "manual", key: "r")]))

    let read = try await store.mergeCandidates(
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      dateRange: epoch.addingTimeInterval(-3600)...epoch.addingTimeInterval(3600)
    )

    let found = try XCTUnwrap(read.first)
    XCTAssertEqual(found.transferPairAtRead, TransferPair(groupID: group, sourceRaw: "manual"))
  }

  /// Amendment 3, item 19. A row read as `(g, manual)` is cleared to `(nil, nil)`
  /// in another context. Applying the stale snapshot with a changed `mergedCount`
  /// must change the count and must not re-create the mark. If the stored pair
  /// comes back `(g, manual)`, the cross-context residual has been measured:
  /// stop and report, do not work around it.
  func testAStaleSnapshotOfAClearedPartnerDoesNotReMarkIt() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let group = TransferGroupID.make(single: UUID())
    let original = snapshot(transferGroupID: group, transferSourceRaw: "manual", key: "p")
    let id = original.id
    try await store.apply(CommitPlan(inserts: [original]))
    let window = epoch.addingTimeInterval(-3600)...epoch.addingTimeInterval(3600)
    let read = try await store.mergeCandidates(
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      dateRange: window
    )
    let stale = try XCTUnwrap(read.first)

    let other = ModelContext(container)
    let row = try XCTUnwrap(
      other.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
    row.transferGroupID = nil
    row.transferSourceRaw = nil
    try other.save()

    var changed = stale
    changed.mergedCount = 5
    try await store.apply(CommitPlan(updates: [changed]))

    let fresh = ModelContext(container)
    let stored = try XCTUnwrap(
      fresh.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })).first
    )
    XCTAssertEqual(stored.mergedCount, 5, "apply ran")
    XCTAssertNil(stored.transferGroupID, "the cleared partner is not re-marked")
    XCTAssertNil(stored.transferSourceRaw)
  }

  /// Amendment 3, rule U3, at reconcile. Two rows, one holding an unrecognised
  /// pair. Reconcile collapses nothing and changes neither row.
  func testReconcileLeavesAGroupWithAnUnrecognizedPairAlone() async throws {
    let container = try makeContainer()
    let store = SwiftDataPipelineStore(modelContainer: container)
    let group = TransferGroupID.make(single: UUID())
    let key = "dup"
    let earlier = snapshot(transferGroupID: nil, transferSourceRaw: "zzz", key: key)
    var later = snapshot(transferGroupID: group, transferSourceRaw: "manual", key: key)
    later.createdAt = epoch.addingTimeInterval(60)
    try await store.apply(CommitPlan(inserts: [earlier, later]))

    let pipeline = IngestPipeline(store: store, calendar: Fixture.calendar, now: Fixture.clock)
    let result = try await pipeline.reconcile()
    XCTAssertEqual(result.groupsCollapsed, 0)
    XCTAssertEqual(result.rowsRemoved, 0)

    let fresh = ModelContext(container)
    let rows = try fresh.fetch(FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.dedupeKey == key }))
    XCTAssertEqual(rows.count, 2)
    let storedEarlier = try XCTUnwrap(rows.first { $0.id == earlier.id })
    let storedLater = try XCTUnwrap(rows.first { $0.id == later.id })
    XCTAssertNil(storedEarlier.transferGroupID)
    XCTAssertEqual(storedEarlier.transferSourceRaw, "zzz")
    XCTAssertEqual(storedLater.transferGroupID, group)
    XCTAssertEqual(storedLater.transferSourceRaw, "manual")
  }
}
