import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// R5. CloudKit rejects `@Attribute(.unique)`, so two devices can each create a
/// locally-unique row for the same transaction and sync will deliver both. The
/// serialized actor protects one device; only this pass protects the account.
final class ReconcileTests: XCTestCase {

  private let food = UUID()
  private let shopping = UUID()

  /// Two rows that CloudKit delivered separately: same key, different ids.
  private func syncedPair(
    description: String = "SWIGGY ORDER",
    firstCreatedAt: String = "2026-08-20 10:00",
    secondCreatedAt: String = "2026-08-21 11:00"
  ) -> (first: TransactionSnapshot, second: TransactionSnapshot) {
    let phone = Fixture.row(
      from: Fixture.draft(description: description, source: .email, externalID: "uid-1"),
      createdAt: firstCreatedAt)
    let pad = Fixture.row(
      from: Fixture.draft(description: description, source: .email, externalID: "uid-1"),
      createdAt: secondCreatedAt)
    return (phone, pad)
  }

  func testRowsSharingADedupeKeyCollapseIntoTheEarliestOne() async throws {
    let pair = syncedPair()
    XCTAssertEqual(pair.first.dedupeKey, pair.second.dedupeKey)
    XCTAssertNotEqual(pair.first.id, pair.second.id)

    let store = FakePipelineStore(rows: [pair.first, pair.second])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result.groupsCollapsed, 1)
    XCTAssertEqual(result.rowsRemoved, 1)

    let count = await store.rowCount
    XCTAssertEqual(count, 1)
    let survivor = await store.row(pair.first.id)
    XCTAssertNotNil(survivor, "the earlier row survives")
    XCTAssertEqual(survivor?.mergedCount, 2)
    XCTAssertEqual(observer.callCount, 1, "one pass, one notification")
  }

  func testCollapsingUnionsContributorsWithoutDuplicatingThem() async throws {
    var phone = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-20 10:00")
    var pad = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-21 11:00")
    // The tablet also saw the CSV; the phone did not.
    pad.sourceRefs.append(
      SourceRef(source: .file, externalID: "REF-9", capturedAt: Fixture.commitTime))
    phone.mergedCount = 1
    pad.mergedCount = 2

    let store = FakePipelineStore(rows: [phone, pad])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.reconcile()

    let survivor = await store.row(phone.id)
    XCTAssertEqual(survivor?.sourceRefs.count, 2, "uid-1 appears once, REF-9 is adopted")
    XCTAssertEqual(survivor?.mergedCount, 3)
  }

  func testAManualCategoryOnEitherSideWinsTheCollapse() async throws {
    var phone = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", externalID: "uid-1"),
      categoryID: food,
      categorySource: .rule,
      createdAt: "2026-08-20 10:00")
    var pad = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", externalID: "uid-1"),
      categoryID: shopping,
      categorySource: .manual,
      createdAt: "2026-08-21 11:00")
    phone.appliedRuleID = UUID()
    pad.appliedRuleID = nil

    let store = FakePipelineStore(rows: [phone, pad])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.reconcile()

    let survivor = await store.row(phone.id)
    XCTAssertEqual(survivor?.categoryID, shopping)
    XCTAssertEqual(survivor?.categorySource, .manual)
    XCTAssertNil(survivor?.appliedRuleID)
  }

  func testConflictingAccountsOnCollapseFlagForReview() async throws {
    let hdfc = UUID()
    let icici = UUID()
    let phone = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", externalID: "uid-1", accountID: hdfc),
      createdAt: "2026-08-20 10:00")
    let pad = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", externalID: "uid-1", accountID: icici),
      createdAt: "2026-08-21 11:00")

    let store = FakePipelineStore(rows: [phone, pad])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.reconcile()

    let survivor = await store.row(phone.id)
    XCTAssertEqual(survivor?.accountID, hdfc)
    XCTAssertTrue(survivor?.needsReview == true)
  }

  func testACleanLedgerIsLeftAloneAndNotifiesNothing() async throws {
    let rows = [
      Fixture.row(from: Fixture.draft(description: "SWIGGY ORDER", externalID: "a")),
      Fixture.row(
        from: Fixture.draft(description: "IRCTC TICKET", amountMinor: 1_240_00, externalID: "b")),
    ]
    let store = FakePipelineStore(rows: rows)
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result, .empty)
    let applies = await store.applyCount
    XCTAssertEqual(applies, 0)
    XCTAssertEqual(observer.callCount, 0)
  }

  func testReconcileIsIdempotent() async throws {
    let pair = syncedPair()
    let store = FakePipelineStore(rows: [pair.first, pair.second])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.reconcile()
    let second = try await pipeline.reconcile()

    XCTAssertEqual(second, .empty)
    let count = await store.rowCount
    XCTAssertEqual(count, 1)
  }
}
