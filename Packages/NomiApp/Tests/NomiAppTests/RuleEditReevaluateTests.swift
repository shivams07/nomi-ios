import Foundation
import NomiCore
import NomiIngest
import SwiftData
import XCTest

@testable import NomiApp

/// Y8: editing a rule releases the rows it set that it no longer claims, then
/// re-applies every rule.
///
/// Before this, `update` and `setScope` re-ran the pass without touching the
/// rows the rule had already categorised. A row the edited pattern no longer
/// reached kept the category the old pattern gave it, with `appliedRuleID`
/// still naming a rule that no longer matched it.
///
/// Fixtures are built the way the app builds them: rows are written, then a
/// rule is created so the real pass categorises them. Each test builds only the
/// rows it asserts on. The spec's rows 2 and 4 share the description
/// `UPI ACT FIBRE`, and a store holding the `*ACT*` rule would move row 2 to
/// Bills, so the rows that need `*ACT*` have their own tests.
@MainActor
final class RuleEditReevaluateTests: XCTestCase {

  /// Owns each test's container for the life of the test. See `InMemoryStack`.
  private var stacks: [InMemoryStack] = []

  private let food = UUID()
  private let bills = UUID()

  // MARK: - Narrowing a pattern

  /// Row 2: it matched `*A*` and not `*AMAZON*`, and no other rule claims it,
  /// so it is released to uncategorised. Row 1 still matches and keeps Food.
  func testNarrowingReleasesRowsItNoLongerMatches() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    XCTAssertEqual(try fetchRow("r2", in: context).categoryID, food, "before: set by *A*")

    try store.update(ruleID, pattern: "*AMAZON*", categoryID: food, scope: .any)

    let released = try fetchRow("r2", in: context)
    XCTAssertNil(released.categoryID)
    XCTAssertEqual(released.categorySourceRaw, CategorySource.none.rawValue)
    XCTAssertNil(released.appliedRuleID)

    let kept = try fetchRow("r1", in: context)
    XCTAssertEqual(kept.categoryID, food, "still matches, so it stays Food")
    XCTAssertEqual(kept.appliedRuleID, ruleID)
  }

  /// Row 3: set by hand to Food. Its `appliedRuleID` is still pointed at the
  /// rule, which is the stale link a fetch on `appliedRuleID` alone would
  /// release. The rule no longer matches it, and it must keep everything.
  func testManualRowsAreNeverReleased() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row(
      "AXIS ATM", key: "r3", amount: 200_000, categoryID: food, source: .manual, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    let atm = try fetchRow("r3", in: context)
    atm.appliedRuleID = ruleID
    try context.save()

    try store.update(ruleID, pattern: "*AMAZON*", categoryID: food, scope: .any)

    let after = try fetchRow("r3", in: context)
    XCTAssertEqual(after.categoryID, food)
    XCTAssertEqual(after.categorySourceRaw, CategorySource.manual.rawValue)
    XCTAssertEqual(after.appliedRuleID, ruleID, "a manual row is not the rule's to release")
  }

  /// Row 4: it was Food by `*A*`, which outranks `*ACT*`. After the edit `*A*`
  /// no longer matches it, and `*ACT*` does, so it lands on Bills in the same
  /// call rather than being left empty.
  func testReleasedRowFallsToTheNextRule() throws {
    let (store, context) = try makeStore()
    try row("UPI ACT FIBRE", key: "r4", amount: 49_900, context: context)
    try context.save()
    try store.create(pattern: "*ACT*", categoryID: bills, scope: .any)
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    let ruleAct = try XCTUnwrap(try ruleNamed("*ACT*", in: context)).id
    XCTAssertEqual(try fetchRow("r4", in: context).appliedRuleID, ruleA, "before: *A* outranks *ACT*")

    try store.update(ruleA, pattern: "*AMAZON*", categoryID: food, scope: .any)

    let fibre = try fetchRow("r4", in: context)
    XCTAssertEqual(fibre.categoryID, bills)
    XCTAssertEqual(fibre.appliedRuleID, ruleAct)
    XCTAssertEqual(fibre.categorySourceRaw, CategorySource.rule.rawValue)
  }

  // MARK: - Scope

  /// Narrowing the scope to debits releases the credit row the rule had set,
  /// and leaves the debit it still matches alone.
  func testSetScopeNarrowingReleasesToo() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "d1", amount: 120_000, context: context)
    try row(
      "UPI AMAZON REFUND", key: "c1", amount: 30_000, direction: .credit, context: context)
    try context.save()
    try store.create(pattern: "*AMAZON*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*AMAZON*", in: context)).id
    XCTAssertEqual(try fetchRow("c1", in: context).categoryID, food, "before: the credit is set")

    try store.setScope(ruleID, RuleScope(direction: .debit))

    let refund = try fetchRow("c1", in: context)
    XCTAssertNil(refund.categoryID, "a credit the scope no longer admits is released")
    XCTAssertNil(refund.appliedRuleID)
    XCTAssertEqual(refund.categorySourceRaw, CategorySource.none.rawValue)
    XCTAssertEqual(try fetchRow("d1", in: context).categoryID, food, "the debit still matches")
  }

  // MARK: - The returned counts

  /// One row released and not re-categorised, one row kept. `matched` counts
  /// only the row that still matches; `recategorized` counts the row that
  /// changed from Food to nothing.
  func testResultCountsReleasedRows() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*A*", in: context)).id

    let result = try store.update(ruleID, pattern: "*AMAZON*", categoryID: food, scope: .any)

    XCTAssertEqual(result.matched, 1, "only the row that still matches")
    XCTAssertEqual(result.recategorized, 1, "the released row moved from Food to nothing")
  }

  /// Food to Bills through `*ACT*` is one row changed. Reapply counts the
  /// released row once for its nil-to-Bills step and the release counts it
  /// again for leaving Food. The result must say one.
  func testReleasedRowMovedByReapplyIsCountedOnce() throws {
    let (store, context) = try makeStore()
    try row("UPI ACT FIBRE", key: "r4", amount: 49_900, context: context)
    try context.save()
    try store.create(pattern: "*ACT*", categoryID: bills, scope: .any)
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id

    let result = try store.update(ruleA, pattern: "*AMAZON*", categoryID: food, scope: .any)

    XCTAssertEqual(result.matched, 1)
    XCTAssertEqual(result.recategorized, 1, "Food to Bills is one row changed, not two")
  }

  /// A released row that the next rule puts back in the category it had
  /// changed nothing, so it must not be counted.
  func testReleasedRowRestoredToTheSameCategoryIsNotCounted() throws {
    let (store, context) = try makeStore()
    try row("UPI ACT FIBRE", key: "r4", amount: 49_900, context: context)
    try context.save()
    try store.create(pattern: "*ACT*", categoryID: food, scope: .any)
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    let ruleAct = try XCTUnwrap(try ruleNamed("*ACT*", in: context)).id

    let result = try store.update(ruleA, pattern: "*AMAZON*", categoryID: food, scope: .any)

    XCTAssertEqual(result.matched, 1)
    XCTAssertEqual(result.recategorized, 0, "Food back to Food changed nothing")
    XCTAssertEqual(try fetchRow("r4", in: context).appliedRuleID, ruleAct)
  }

  // MARK: - Edges

  /// A disabled rule set nothing it still claims, so editing it releases
  /// nothing. Its rows keep the category and the link they had.
  func testDisabledRuleEditReleasesNothing() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    try store.setEnabled(ruleA, false)

    try store.update(ruleA, pattern: "*AMAZON*", categoryID: food, scope: .any)

    let fibre = try fetchRow("r2", in: context)
    XCTAssertEqual(fibre.categoryID, food)
    XCTAssertEqual(fibre.appliedRuleID, ruleA)
    XCTAssertEqual(try fetchRow("r1", in: context).appliedRuleID, ruleA)
  }

  /// The category changed but the pattern still matches: the rows it set move
  /// to the new category, and each is counted once.
  func testCategoryChangeReassignsRowsItStillMatches() throws {
    let (store, context) = try makeStore()
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id

    let result = try store.update(ruleA, pattern: "*A*", categoryID: bills, scope: .any)

    for key in ["r1", "r2"] {
      let moved = try fetchRow(key, in: context)
      XCTAssertEqual(moved.categoryID, bills, key)
      XCTAssertEqual(moved.appliedRuleID, ruleA, key)
    }
    XCTAssertEqual(result.matched, 2)
    XCTAssertEqual(result.recategorized, 2)
  }

  // MARK: - Post-commit and rewrites

  /// Records each affected set the coordinator hands its observer.
  final class SpyCommit: PostCommitObserver, @unchecked Sendable {
    private(set) var calls: [Set<UUID>] = []
    func didCommit(affectedCategoryIDs: Set<UUID>) async { calls.append(affectedCategoryIDs) }
  }

  /// Scenario A. The released row was Food, so the commit must name Food, and
  /// the whole call is one commit. Without the released categories in the
  /// seed, no commit fires at all and the Insights cache and budget alerts
  /// keep the pre-edit total.
  func testScenarioAReportsTheReleasedCategoryInOneCommit() async throws {
    let context = try makeContext()
    let (store, coordinator) = makeStore(in: context)
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try row("AXIS ATM", key: "r3", amount: 200_000, categoryID: food, source: .manual, context: context)
    try context.save()
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    XCTAssertEqual(totals(context)["Food"], 419_900, "before Food 4,199.00")

    let spy = SpyCommit()
    coordinator.setObserver(spy)
    let result = try store.update(ruleID, pattern: "*AMAZON*", categoryID: food, scope: .any)
    try await settle()

    let after = totals(context)
    XCTAssertEqual(after["Food"], 320_000, "after Food 3,200.00")
    XCTAssertEqual(after["Uncategorised"], 99_900, "after Uncategorised 999.00")
    XCTAssertEqual(after.values.reduce(0, +), 419_900, "total unchanged")
    XCTAssertEqual(result.matched, 1)
    XCTAssertEqual(result.recategorized, 1)
    XCTAssertEqual(spy.calls.count, 1, "exactly one didWrite")
    XCTAssertEqual(spy.calls.first, [food], "released Food must be in the affected set")
  }

  /// Scenario B. The released row is re-categorised to Bills in the same call,
  /// and the one commit names both categories.
  func testScenarioBReportsBothCategoriesInOneCommit() async throws {
    let context = try makeContext()
    let (store, coordinator) = makeStore(in: context)
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("AXIS ATM", key: "r3", amount: 200_000, categoryID: food, source: .manual, context: context)
    try row("UPI ACT FIBRE", key: "r4", amount: 49_900, context: context)
    try context.save()
    try store.create(pattern: "*ACT*", categoryID: bills, scope: .any)
    try store.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleA = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    XCTAssertEqual(totals(context)["Food"], 369_900, "before Food 3,699.00")
    XCTAssertNil(totals(context)["Bills"], "no Bills before the edit")

    let spy = SpyCommit()
    coordinator.setObserver(spy)
    let result = try store.update(ruleA, pattern: "*AMAZON*", categoryID: food, scope: .any)
    try await settle()

    let after = totals(context)
    XCTAssertEqual(after["Food"], 320_000, "after Food 3,200.00")
    XCTAssertEqual(after["Bills"], 49_900, "after Bills 499.00")
    XCTAssertEqual(after.values.reduce(0, +), 369_900, "total unchanged")
    XCTAssertEqual(try fetchRow("r4", in: context).categoryID, bills)
    XCTAssertEqual(result.matched, 2)
    XCTAssertEqual(result.recategorized, 1)
    XCTAssertEqual(spy.calls.count, 1, "one didWrite for the whole call")
    XCTAssertEqual(spy.calls.first, [food, bills])
  }

  /// A row the edit still matches, with its category unchanged, must not be
  /// rewritten: `updatedAt` stays where the seeding pass put it. Only this
  /// assertion sees a release-everything implementation, since the category
  /// totals come out the same either way.
  func testAStillMatchedRowIsNotRewritten() async throws {
    let context = try makeContext()
    let (seedStore, _) = makeStore(in: context)
    try row("UPI AMAZON PAY", key: "r1", amount: 120_000, context: context)
    try row("UPI ACT FIBRE", key: "r2", amount: 99_900, context: context)
    try context.save()
    try seedStore.create(pattern: "*A*", categoryID: food, scope: .any)
    let ruleID = try XCTUnwrap(try ruleNamed("*A*", in: context)).id
    let seededAt = try fetchRow("r1", in: context).updatedAt

    let later = Date(timeIntervalSince1970: 2_000_000_000)
    let (editStore, coordinator) = makeStore(in: context, now: { later })
    let spy = SpyCommit()
    coordinator.setObserver(spy)
    try editStore.update(ruleID, pattern: "*AMAZON*", categoryID: food, scope: .any)
    try await settle()

    let kept = try fetchRow("r1", in: context)
    XCTAssertEqual(kept.updatedAt, seededAt, "a still-matched row must not be rewritten")
    XCTAssertEqual(kept.categoryID, food)
    XCTAssertEqual(spy.calls.first, [food], "the released ACT row's Food is in the affected set")
  }

  /// The observer is reached through a detached task, so give it a turn.
  private func settle() async throws {
    try await Task.sleep(nanoseconds: 100_000_000)
  }

  // MARK: - Helpers

  private func makeContext() throws -> ModelContext {
    let stack = try InMemoryStack()
    stacks.append(stack)
    return stack.context
  }

  /// A store over an existing context, so two stores can share one ledger, with
  /// the clock injected for the rewrite test.
  private func makeStore(
    in context: ModelContext,
    now: @escaping () -> Date = { Date() }
  ) -> (SwiftDataRuleStore, WriteCoordinator) {
    let coordinator = WriteCoordinator(cache: InsightsCache())
    return (SwiftDataRuleStore(context: context, coordinator: coordinator, now: now), coordinator)
  }

  /// Category totals in minor units, keyed by category, read from the rows.
  private func totals(_ context: ModelContext) -> [String: Int] {
    var out: [String: Int] = [:]
    let rows = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
    for transaction in rows {
      let key: String
      if transaction.categoryID == nil {
        key = "Uncategorised"
      } else if transaction.categoryID == food {
        key = "Food"
      } else if transaction.categoryID == bills {
        key = "Bills"
      } else {
        key = "other"
      }
      out[key, default: 0] += transaction.amountMinor
    }
    return out
  }

  /// A store on its own in-memory container, the way `RulePriorityTests` builds
  /// one, so no row or rule from one test reaches the next.
  private func makeStore() throws -> (SwiftDataRuleStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let context = stack.context
    let store = SwiftDataRuleStore(
      context: context, coordinator: WriteCoordinator(cache: InsightsCache()))
    return (store, context)
  }

  @discardableResult
  private func row(
    _ description: String,
    key: String,
    amount: Int,
    direction: Direction = .debit,
    categoryID: UUID? = nil,
    source: CategorySource = .none,
    context: ModelContext
  ) throws -> Transaction {
    let transaction = Transaction(
      descriptionText: description,
      normalizedDescription: description,
      amountMinor: amount,
      directionRaw: direction.rawValue,
      categoryID: categoryID,
      categorySourceRaw: source.rawValue,
      dedupeKey: key)
    context.insert(transaction)
    return transaction
  }

  private func fetchRow(_ key: String, in context: ModelContext) throws -> Transaction {
    let rows = try context.fetch(FetchDescriptor<Transaction>())
    return try XCTUnwrap(rows.first { $0.dedupeKey == key }, "no row \(key)")
  }

  private func ruleNamed(_ pattern: String, in context: ModelContext) throws -> Rule? {
    try context.fetch(FetchDescriptor<Rule>()).first { $0.pattern == pattern }
  }
}
