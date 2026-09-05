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

  // MARK: - C1: reconcile never removes a row the user typed

  /// A manual row equivalent to what `SwiftDataTransactionStore.add` writes:
  /// `source == .manual`, one manual `SourceRef`.
  private func manualRow(
    externalID: String,
    createdAt: String,
    description: String = "SWIGGY ORDER"
  ) -> TransactionSnapshot {
    Fixture.row(
      from: Fixture.draft(description: description, source: .manual, externalID: externalID),
      createdAt: createdAt)
  }

  /// Two rows the user typed twice are not the app's to merge. Collapsing them
  /// would silently delete one of them; the pair is left for the user to sort
  /// out. FAILS against `main`, which collapses on `createdAt` alone.
  func testTwoManualRowsSharingAKeyAreLeftForTheUser() async throws {
    let first = manualRow(externalID: "m-1", createdAt: "2026-08-20 10:00")
    let second = manualRow(externalID: "m-2", createdAt: "2026-08-21 11:00")
    XCTAssertEqual(first.dedupeKey, second.dedupeKey)

    let store = FakePipelineStore(rows: [first, second])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result.groupsCollapsed, 0)
    XCTAssertEqual(result.rowsRemoved, 0)
    let count = await store.rowCount
    XCTAssertEqual(count, 2, "both rows the user typed are still there")
    let survivingFirst = await store.row(first.id)
    let survivingSecond = await store.row(second.id)
    XCTAssertNotNil(survivingFirst)
    XCTAssertNotNil(survivingSecond)
    let applies = await store.applyCount
    XCTAssertEqual(applies, 0)
    XCTAssertEqual(observer.callCount, 0)
  }

  /// The documented purpose of the second write path: the user typed a row the
  /// mail sync then found. It still collapses to one row, but the survivor is
  /// the one the user typed - even though it was created later.
  func testAManualRowOutranksAnEarlierEmailRowInACollapse() async throws {
    let email = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-20 10:00")
    let manual = manualRow(externalID: "m-1", createdAt: "2026-08-21 11:00")
    XCTAssertEqual(email.dedupeKey, manual.dedupeKey)

    let store = FakePipelineStore(rows: [email, manual])
    let pipeline = await Fixture.pipeline(store: store)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result.groupsCollapsed, 1)
    XCTAssertEqual(result.rowsRemoved, 1)
    let count = await store.rowCount
    XCTAssertEqual(count, 1)
    let survivor = await store.row(manual.id)
    let removed = await store.row(email.id)
    XCTAssertNotNil(survivor, "the manual row survives, not the earlier email one")
    XCTAssertNil(removed)
    XCTAssertEqual(survivor?.mergedCount, 2)
    let refs = survivor?.sourceRefs ?? []
    XCTAssertEqual(refs.count, 2, "the email contributor is adopted")
    XCTAssertTrue(refs.contains(where: { $0.source == .manual }))
    XCTAssertTrue(refs.contains(where: { $0.source == .email }))
  }

  /// One manual row, several email rows: the manual row is the survivor and
  /// every email row folds into it.
  func testOneManualRowSurvivesAgainstSeveralEmailRows() async throws {
    let manual = manualRow(externalID: "m-1", createdAt: "2026-08-19 09:00")
    let phone = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-20 10:00")
    let pad = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-2"),
      createdAt: "2026-08-21 11:00")

    let store = FakePipelineStore(rows: [manual, phone, pad])
    let pipeline = await Fixture.pipeline(store: store)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result.groupsCollapsed, 1)
    XCTAssertEqual(result.rowsRemoved, 2)
    let survivor = await store.row(manual.id)
    XCTAssertNotNil(survivor)
    XCTAssertEqual(survivor?.mergedCount, 3)
    XCTAssertEqual(survivor?.sourceRefs.count, 3)
  }

  /// Two manual rows plus an email row: nothing is collapsed at all, including
  /// the email row. The conservative direction - the app cannot know which
  /// manual row the email belongs to.
  func testTwoManualRowsBlockTheWholeGroupIncludingAnEmailRow() async throws {
    let first = manualRow(externalID: "m-1", createdAt: "2026-08-19 09:00")
    let second = manualRow(externalID: "m-2", createdAt: "2026-08-20 10:00")
    let email = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1"),
      createdAt: "2026-08-21 11:00")

    let store = FakePipelineStore(rows: [first, second, email])
    let pipeline = await Fixture.pipeline(store: store)

    let result = try await pipeline.reconcile()

    XCTAssertEqual(result, .empty)
    let count = await store.rowCount
    XCTAssertEqual(count, 3)
  }
}
