import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiIngest

/// `SwiftDataPipelineStore` used to describe itself as compile-verified only:
/// "nothing below this line is executed by any test on this project." That was
/// true, for a reason nobody had isolated — see the rewritten note in
/// `NomiCore/Support/InMemoryModelContainer.swift`. It is not a property of
/// this package, and this file is the demonstration: a real `ModelContainer`,
/// the `@ModelActor`'s own generated `init(modelContainer:)`, and the four
/// store operations `IngestPipeline` actually calls.
///
/// **XCTest, and it has to stay XCTest.** Written under swift-testing, every
/// test here traps on `ModelContainer` construction. Every other test in this
/// package is XCTest already, so nothing about this file looks unusual — which
/// is exactly why this paragraph is here.
final class SwiftDataPipelineStoreTests: XCTestCase {

  /// The app's schema, spelled out here because `NomiModelContainer.schema`
  /// lives in NomiApp and this package cannot see it. Kept in the same order
  /// as `InMemoryModelContainer` so a drift is visible side by side.
  private static func makeContainer() throws -> ModelContainer {
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
    let configuration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try ModelContainer(for: schema, configurations: [configuration])
  }

  /// The `@ModelActor` macro's generated `init(modelContainer:)`, which is
  /// where the actor's `ModelContext` is built.
  func testTheModelActorIsConstructible() throws {
    _ = SwiftDataPipelineStore(modelContainer: try Self.makeContainer())
  }

  /// A plan's inserts become rows, and the rows come back as snapshots through
  /// the same `PipelineStore` contract `IngestPipeline` calls.
  func testAppliedInsertsAreReadBackAsSnapshots() async throws {
    let store = SwiftDataPipelineStore(modelContainer: try Self.makeContainer())
    let swiggy = Fixture.row(from: Fixture.draft(description: "UPI/P2M/1/SWIGGY", amountMinor: 45_900))
    let uber = Fixture.row(from: Fixture.draft(description: "UPI/P2M/2/UBER", amountMinor: 21_000, externalID: "uid-2"))

    try await store.apply(CommitPlan(inserts: [swiggy, uber]))

    let rows = try await store.rulePassCandidates()
    XCTAssertEqual(Set(rows.map(\.id)), Set([swiggy.id, uber.id]))
    XCTAssertEqual(rows.first(where: { $0.id == swiggy.id })?.amountMinor, 45_900)
    XCTAssertEqual(rows.first(where: { $0.id == swiggy.id })?.dedupeKey, swiggy.dedupeKey)
  }

  /// Updates mutate the stored row rather than adding one, and deletes remove
  /// it. Both go through `fetchRow(id:)` and a `#Predicate` on `id`.
  func testUpdatesAndDeletesLandOnTheStoredRow() async throws {
    let store = SwiftDataPipelineStore(modelContainer: try Self.makeContainer())
    var row = Fixture.row(from: Fixture.draft())

    try await store.apply(CommitPlan(inserts: [row]))

    row.needsReview = true
    row.mergedCount = 2
    try await store.apply(CommitPlan(updates: [row]))

    let afterUpdate = try await store.rulePassCandidates()
    XCTAssertEqual(afterUpdate.count, 1)
    XCTAssertEqual(afterUpdate.first?.needsReview, true)
    XCTAssertEqual(afterUpdate.first?.mergedCount, 2)

    try await store.apply(CommitPlan(deletes: [row.id]))
    let afterDelete = try await store.rulePassCandidates()
    XCTAssertTrue(afterDelete.isEmpty)
  }

  /// The actor's own `ModelContext` and a plain `ModelContext` on the same
  /// container see each other. `rules()` is the read `IngestPipeline` makes on
  /// every batch, and nothing in this package ever writes a `Rule` — the app
  /// does, from a different context.
  func testTheActorReadsRowsWrittenByAnotherContextOnTheSameContainer() async throws {
    let container = try Self.makeContainer()
    let context = ModelContext(container)
    let enabled = UUID()

    context.insert(Rule(id: enabled, pattern: "SWIGGY*", categoryID: UUID(), priority: 5))
    context.insert(Rule(pattern: "UBER*", categoryID: UUID(), priority: 1, isEnabled: false))
    try context.save()

    let store = SwiftDataPipelineStore(modelContainer: container)
    let rules = try await store.rules()

    XCTAssertEqual(rules.map(\.id), [enabled])
    XCTAssertEqual(rules.first?.pattern, "SWIGGY*")
  }

  /// A date-range plus amount predicate — the merge lookup, and the only
  /// `FetchDescriptor` here with a comparison rather than an equality.
  func testMergeCandidatesFilterOnAmountDirectionAndDateRange() async throws {
    let store = SwiftDataPipelineStore(modelContainer: try Self.makeContainer())
    let inRange = Fixture.row(from: Fixture.draft(date: "2026-08-20", amountMinor: 45_900))
    let wrongAmount = Fixture.row(from: Fixture.draft(date: "2026-08-20", amountMinor: 45_901, externalID: "uid-2"))
    let outOfRange = Fixture.row(from: Fixture.draft(date: "2026-07-01", amountMinor: 45_900, externalID: "uid-3"))

    try await store.apply(CommitPlan(inserts: [inRange, wrongAmount, outOfRange]))

    let matches = try await store.mergeCandidates(
      amountMinor: 45_900,
      directionRaw: Direction.debit.rawValue,
      dateRange: Fixture.date("2026-08-18")...Fixture.date("2026-08-22")
    )

    XCTAssertEqual(matches.map(\.id), [inRange.id])
  }
}
