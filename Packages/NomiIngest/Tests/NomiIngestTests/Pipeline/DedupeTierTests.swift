import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Tier 1 (exact key) and tier 2 (+/-2 days, similarity >= 0.9).
final class DedupeTierTests: XCTestCase {

  // MARK: - Tier 1

  func testExactReIngestOfTheSameContributorCreatesZeroRowsAndChangesNothing() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    let draft = Fixture.draft()

    let first = try await pipeline.ingest([draft])
    XCTAssertEqual(first.created, 1)

    let second = try await pipeline.ingest([draft])
    XCTAssertEqual(second.created, 0, "a re-ingest must never create a row")
    XCTAssertEqual(second.merged, 1)

    let count = await store.rowCount
    XCTAssertEqual(count, 1)

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.mergedCount, 1, "the same contributor twice is a no-op, not a merge")
    XCTAssertEqual(row.sourceRefs.count, 1)
    XCTAssertFalse(row.needsReview)

    // Second pass committed nothing at all.
    let applies = await store.applyCount
    XCTAssertEqual(applies, 1)
  }

  func testReImportingTheSameFileWithRowsReorderedIsANoOp() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    let rows = [
      Fixture.draft(description: "NEFT SALARY CREDIT", amountMinor: 12_000_00,
                    direction: .credit, source: .file, externalID: "REF-001"),
      Fixture.draft(description: "AMAZON RETAIL", amountMinor: 2_499_00,
                    source: .file, externalID: "REF-002"),
      Fixture.draft(description: "UBER TRIP", amountMinor: 318_00,
                    source: .file, externalID: "REF-003"),
    ]

    _ = try await pipeline.ingest(rows)
    let again = try await pipeline.ingest(rows.reversed())

    XCTAssertEqual(again.created, 0)
    XCTAssertEqual(again.merged, 3)
    let count = await store.rowCount
    XCTAssertEqual(count, 3)
  }

  func testSecondContributorForTheSameTransactionMergesAndCounts() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([Fixture.draft(externalID: "uid-1")])
    // The bank sent the alert twice under two UIDs.
    _ = try await pipeline.ingest([Fixture.draft(externalID: "uid-2")])

    let count = await store.rowCount
    XCTAssertEqual(count, 1)
    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.mergedCount, 2)
    XCTAssertEqual(row.sourceRefs.count, 2)
  }

  // MARK: - Tier 2

  func testNearMatchTwoDaysApartMergesAndSetsNeedsReview() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-20", description: "SWIGGY ORDER PAYMENT",
                    source: .email, externalID: "uid-1")
    ])
    let second = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-22", description: "SWIGGY ORDER PAYMENTS",
                    source: .file, externalID: "REF-77")
    ])

    XCTAssertEqual(second.created, 0)
    XCTAssertEqual(second.merged, 1)
    XCTAssertEqual(second.flagged, 1)

    let count = await store.rowCount
    XCTAssertEqual(count, 1, "the bank alert and the CSV posting date are one transaction")
    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertTrue(row.needsReview, "a near merge is always flagged")
    XCTAssertEqual(row.mergedCount, 2)
    XCTAssertEqual(row.date, Fixture.date("2026-08-20"), "the surviving row keeps its own date")
    XCTAssertEqual(row.descriptionText, "SWIGGY ORDER PAYMENT", "narration is never rewritten")
  }

  func testThreeDaysApartIsOutsideTheWindowAndStaysTwoRows() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-20", description: "SWIGGY ORDER PAYMENT", externalID: "a")
    ])
    _ = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-23", description: "SWIGGY ORDER PAYMENTS", externalID: "b")
    ])

    let count = await store.rowCount
    XCTAssertEqual(count, 2)
  }

  func testDissimilarNarrationDoesNotMergeEvenOnTheSameDayAndAmount() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-20", description: "SWIGGY ORDER", externalID: "a")
    ])
    _ = try await pipeline.ingest([
      Fixture.draft(date: "2026-08-20", description: "BLINKIT GROCERY", externalID: "b")
    ])

    let count = await store.rowCount
    XCTAssertEqual(count, 2, "same amount and day is not enough; the description must match too")
  }

  func testDifferentDirectionNeverMerges() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([Fixture.draft(direction: .debit, externalID: "a")])
    _ = try await pipeline.ingest([Fixture.draft(direction: .credit, externalID: "b")])

    let count = await store.rowCount
    XCTAssertEqual(count, 2)
  }

  // MARK: - Merge field resolution

  func testConflictingAccountIDsKeepTheEarlierOneAndFlagForReview() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    let hdfc = UUID()
    let icici = UUID()

    _ = try await pipeline.ingest([Fixture.draft(externalID: "a", accountID: hdfc)])
    _ = try await pipeline.ingest([Fixture.draft(externalID: "b", accountID: icici)])

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.accountID, hdfc)
    XCTAssertTrue(row.needsReview)
  }

  func testAnUnidentifiedRowAdoptsTheAccountOfALaterContributor() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)
    let hdfc = UUID()

    _ = try await pipeline.ingest([Fixture.draft(externalID: "a", accountID: nil)])
    _ = try await pipeline.ingest([Fixture.draft(externalID: "b", accountID: hdfc)])

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.accountID, hdfc)
    XCTAssertFalse(row.needsReview, "filling a gap is not a conflict")
  }
}
