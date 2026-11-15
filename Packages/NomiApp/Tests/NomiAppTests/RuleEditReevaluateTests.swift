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

  // MARK: - Helpers

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
