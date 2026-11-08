import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// DEC-05 A-05 items 11, 16 and 17, on the SwiftData side: the five optional
/// `TransactionSnapshot` fields survive every copy site, a stale pipeline write
/// cannot undo a user's mark, and a collapse keeps a duplicate's mark.
///
/// XCTest, and it stays XCTest: a `ModelContainer` traps under swift-testing
/// (see `SwiftDataPipelineStoreTests`). Deferred to Xcode; not run on the CLT.
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

  private func snapshot(
    id: UUID = UUID(),
    source: String = IngestSource.email.rawValue,
    transferGroupID: UUID? = nil,
    transferSourceRaw: String? = nil,
    key: String = "k"
  ) -> TransactionSnapshot {
    TransactionSnapshot(
      id: id,
      date: epoch,
      descriptionText: "HDFC CREDIT CARD PAYMENT",
      normalizedDescription: "HDFC CREDIT CARD PAYMENT",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      sourceRaw: source,
      dedupeKey: key,
      createdAt: epoch,
      updatedAt: epoch,
      senderDomain: nil,
      cardFragment: nil,
      needsReviewReason: nil,
      transferGroupID: transferGroupID,
      transferSourceRaw: transferSourceRaw
    )
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

  /// Item 16. A snapshot read before a user marks a row, applied after, leaves
  /// the mark alone; a nil snapshot does not erase an auto mark.
  func testAStaleSnapshotNeverOverridesAUserDecision() {
    let group = TransferGroupID.make(single: UUID())

    let manual = Transaction(dedupeKey: "k", transferGroupID: group, transferSourceRaw: "manual")
    manual.apply(snapshot(transferGroupID: nil, transferSourceRaw: nil))
    XCTAssertEqual(manual.transferGroupID, group)
    XCTAssertEqual(manual.transferSourceRaw, "manual")

    let rejected = Transaction(dedupeKey: "k", transferGroupID: nil, transferSourceRaw: "rejected")
    rejected.apply(snapshot(transferGroupID: group, transferSourceRaw: "auto"))
    XCTAssertNil(rejected.transferGroupID)
    XCTAssertEqual(rejected.transferSourceRaw, "rejected")

    let auto = Transaction(dedupeKey: "k", transferGroupID: group, transferSourceRaw: "auto")
    auto.apply(snapshot(transferGroupID: nil, transferSourceRaw: nil))
    XCTAssertEqual(auto.transferGroupID, group, "a nil snapshot never erases an auto mark")
  }

  /// Item 16, the other half: an unmarked row takes an automatic mark, and both
  /// fields arrive together.
  func testApplyWritesAnAutoMarkOntoAnUnmarkedRow() {
    let group = TransferGroupID.make(single: UUID())
    let row = Transaction(dedupeKey: "k")
    row.apply(snapshot(transferGroupID: group, transferSourceRaw: "auto"))
    XCTAssertEqual(row.transferGroupID, group)
    XCTAssertEqual(row.transferSourceRaw, "auto")
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
}
