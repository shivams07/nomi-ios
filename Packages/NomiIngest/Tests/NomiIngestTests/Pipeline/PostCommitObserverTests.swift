import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The v5 hook: invoked once per commit batch with the set of affected
/// category ids. U10 implements it, U8 wires it, and U4 does not know budgets
/// exist — note that nothing in this file mentions one.
final class PostCommitObserverTests: XCTestCase {

  private let food = UUID()
  private let travel = UUID()

  func testTheObserverFiresOncePerBatchNotOncePerRow() async throws {
    let store = FakePipelineStore(rules: [Fixture.rule(pattern: "*SWIGGY*", categoryID: food)])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    let drafts = (1...5).map { index in
      Fixture.draft(
        description: "SWIGGY ORDER \(index)",
        amountMinor: 100_00 * index,
        externalID: "uid-\(index)")
    }
    let result = try await pipeline.ingest(drafts)

    XCTAssertEqual(result.created, 5)
    let applies = await store.applyCount
    XCTAssertEqual(applies, 1, "five rows, one commit")
    XCTAssertEqual(observer.callCount, 1, "five rows, one notification")
    XCTAssertEqual(observer.calls.first, Set([food]))
  }

  func testEachBatchIsItsOwnNotification() async throws {
    let store = FakePipelineStore(rules: [Fixture.rule(pattern: "*SWIGGY*", categoryID: food)])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    _ = try await pipeline.ingest([Fixture.draft(description: "SWIGGY ONE", externalID: "a")])
    _ = try await pipeline.ingest([
      Fixture.draft(description: "SWIGGY TWO", amountMinor: 200_00, externalID: "b")
    ])

    XCTAssertEqual(observer.callCount, 2)
  }

  func testABatchThatCommitsNothingDoesNotNotify() async throws {
    let store = FakePipelineStore()
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)
    let draft = Fixture.draft()

    _ = try await pipeline.ingest([draft])
    XCTAssertEqual(observer.callCount, 1)

    _ = try await pipeline.ingest([draft])
    XCTAssertEqual(observer.callCount, 1, "a no-op re-ingest is not a commit")

    _ = try await pipeline.ingest([])
    XCTAssertEqual(observer.callCount, 1)
  }

  func testTheAffectedSetCarriesBothSidesOfARecategorization() async throws {
    let oldRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: travel, priority: 5)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: travel,
      categorySource: .rule,
      appliedRuleID: oldRule.id)
    let newRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1)
    let store = FakePipelineStore(rows: [row], rules: [oldRule, newRule])
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    _ = try await pipeline.reapplyRules()

    XCTAssertEqual(observer.callCount, 1)
    XCTAssertEqual(
      observer.calls.first, Set([travel, food]),
      "the category a row left matters as much as the one it joined")
  }

  func testAnUncategorizedRowContributesNothingToTheAffectedSet() async throws {
    let store = FakePipelineStore()
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    _ = try await pipeline.ingest([Fixture.draft(description: "MYSTERY DEBIT")])

    XCTAssertEqual(observer.callCount, 1)
    XCTAssertEqual(observer.calls.first, Set<UUID>())
  }

  func testDetachingTheObserverStopsNotifications() async throws {
    let store = FakePipelineStore()
    let observer = RecordingObserver()
    let pipeline = await Fixture.pipeline(store: store, observer: observer)

    _ = try await pipeline.ingest([Fixture.draft(externalID: "a")])
    await pipeline.setObserver(nil)
    _ = try await pipeline.ingest([
      Fixture.draft(description: "OTHER", amountMinor: 1_00, externalID: "b")
    ])

    XCTAssertEqual(observer.callCount, 1)
  }
}
