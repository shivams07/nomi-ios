import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// "Concurrent writes from mail sync and file import must not race."
///
/// The race is a check-then-act: two callers both read the merge candidates,
/// both find nothing, and both insert. `actor` alone does NOT close it — Swift
/// actors are reentrant, and the first version of this unit failed the second
/// test below on CI with a mergedCount of 3 out of 12. What closes it is the
/// mutex `IngestPipeline` holds across the whole read-decide-write span.
final class SerializedWriteTests: XCTestCase {

  func testAMailSyncAndAFileImportForTheSameTransactionProduceOneRow() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    async let mail: IngestBatchResult = pipeline.ingest([
      Fixture.draft(source: .email, externalID: "uid-1")
    ])
    async let file: IngestBatchResult = pipeline.ingest([
      Fixture.draft(source: .file, externalID: "REF-1")
    ])
    let results = [try await mail, try await file]

    let count = await store.rowCount
    XCTAssertEqual(count, 1, "whichever ran second must have seen the first")
    XCTAssertEqual(results.map(\.created).reduce(0, +), 1)
    XCTAssertEqual(results.map(\.merged).reduce(0, +), 1)

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.mergedCount, 2)
  }

  func testManyConcurrentIngestsOfTheSameTransactionStillProduceOneRow() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    try await withThrowingTaskGroup(of: IngestBatchResult.self) { group in
      for index in 1...12 {
        group.addTask {
          try await pipeline.ingest([Fixture.draft(externalID: "uid-\(index)")])
        }
      }
      var created = 0
      for try await result in group { created += result.created }
      XCTAssertEqual(created, 1)
    }

    let count = await store.rowCount
    XCTAssertEqual(count, 1)
    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.mergedCount, 12)
    XCTAssertEqual(row.sourceRefs.count, 12)
  }

  func testConcurrentIngestsOfDifferentTransactionsAllLand() async throws {
    let store = FakePipelineStore()
    let pipeline = await Fixture.pipeline(store: store)

    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 1...10 {
        group.addTask {
          _ = try await pipeline.ingest([
            Fixture.draft(
              description: "MERCHANT \(index)",
              amountMinor: 1_000 * index,
              externalID: "uid-\(index)")
          ])
        }
      }
      try await group.waitForAll()
    }

    let count = await store.rowCount
    XCTAssertEqual(count, 10)
  }
}
