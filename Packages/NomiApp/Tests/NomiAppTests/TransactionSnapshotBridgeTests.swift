import Foundation
import NomiCore
import NomiIngest
import XCTest

@testable import NomiApp

/// DEC-05 A-05 item 11, through NomiApp's bridge. Before T1 this bridge dropped
/// the three C4 fields without a compile error, because the snapshot initialiser
/// defaulted them. The initialiser has no defaults now, so this test is the
/// behavioural half: every field the bridge reads comes back out of it.
///
/// XCTest, deferred to Xcode with the rest of the SwiftData-backed tests. It
/// builds `Transaction` values without a container, which needs no runner.
final class TransactionSnapshotBridgeTests: XCTestCase {

  func testTheBridgeCarriesTheC4FieldsAndTheTransferPair() {
    let group = UUID()
    let row = Transaction(
      date: Date(timeIntervalSince1970: 1_700_000_000),
      descriptionText: "HDFC CREDIT CARD PAYMENT",
      normalizedDescription: "HDFC CREDIT CARD PAYMENT",
      amountMinor: 2_000_000,
      directionRaw: Direction.debit.rawValue,
      sourceRaw: IngestSource.email.rawValue,
      dedupeKey: "k",
      senderDomain: "hdfcbank.net",
      cardFragment: "6411",
      needsReviewReasonRaw: NeedsReviewReason.heuristic.rawValue,
      transferGroupID: group,
      transferSourceRaw: TransferSource.auto.rawValue
    )

    let snapshot = TransactionSnapshot(row)

    XCTAssertEqual(snapshot.senderDomain, "hdfcbank.net")
    XCTAssertEqual(snapshot.cardFragment, "6411")
    XCTAssertEqual(snapshot.needsReviewReason, .heuristic)
    XCTAssertEqual(snapshot.transferGroupID, group)
    XCTAssertEqual(snapshot.transferSourceRaw, TransferSource.auto.rawValue)
  }

  func testAPlainRowBridgesToAPlainSnapshot() {
    let row = Transaction(dedupeKey: "k")
    let snapshot = TransactionSnapshot(row)
    XCTAssertNil(snapshot.senderDomain)
    XCTAssertNil(snapshot.cardFragment)
    XCTAssertNil(snapshot.needsReviewReason)
    XCTAssertNil(snapshot.transferGroupID)
    XCTAssertNil(snapshot.transferSourceRaw)
  }
}
