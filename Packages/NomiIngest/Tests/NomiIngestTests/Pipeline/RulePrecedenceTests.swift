import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Rule precedence, and the three lifecycle passes: ingest, retroactive
/// re-apply, delete.
final class RulePrecedenceTests: XCTestCase {

  private let food = UUID()
  private let shopping = UUID()
  private let travel = UUID()

  // MARK: - Precedence

  func testLowerPriorityWinsAndEvaluationStopsAtTheFirstMatch() {
    let rules = [
      Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5),
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1),
    ]
    let match = RuleEngine.firstMatch(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)
    XCTAssertEqual(match?.categoryID, food)
  }

  func testUnderEqualPriorityTheOlderRuleWinsRegardlessOfFetchOrder() {
    let older = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: food, priority: 0, createdAt: "2026-01-01")
    let newer = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: shopping, priority: 0, createdAt: "2026-06-01")

    for ordering in [[older, newer], [newer, older]] {
      let match = RuleEngine.firstMatch(normalizedDescription: "SWIGGY ORDER", in: ordering)
      XCTAssertEqual(match?.id, older.id)
    }
  }

  /// Equal priority *and* equal `createdAt` is the case the design leaves
  /// open. Whatever the winner is, it must be the same winner every time — a
  /// CloudKit-backed fetch does not promise a stable row order.
  func testEqualPriorityAndEqualTimestampResolveDeterministically() {
    let a = Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 0, createdAt: "2026-01-01")
    let b = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: shopping, priority: 0, createdAt: "2026-01-01")
    let c = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: travel, priority: 0, createdAt: "2026-01-01")

    let permutations = [[a, b, c], [c, b, a], [b, c, a], [a, c, b], [c, a, b], [b, a, c]]
    let winners = permutations.compactMap {
      RuleEngine.firstMatch(normalizedDescription: "SWIGGY ORDER", in: $0)?.id
    }

    XCTAssertEqual(winners.count, permutations.count)
    XCTAssertEqual(Set(winners).count, 1, "the same rule must win from every fetch order")
    XCTAssertEqual(winners[0], [a, b, c].map(\.id).min(by: { $0.uuidString < $1.uuidString }))
  }

  func testDisabledRulesNeverMatch() {
    let rules = [
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 0, isEnabled: false)
    ]
    XCTAssertNil(RuleEngine.firstMatch(normalizedDescription: "SWIGGY ORDER", in: rules))
  }

  // MARK: - On ingest

  func testARuleAssignsTheCategoryAndRecordsProvenanceOnIngest() async throws {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let store = FakePipelineStore(rules: [rule])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([Fixture.draft(description: "UPI/P2M/9911/SWIGGY/HDFC/Order")])

    let onlyRow = await store.onlyRow
    let row = try XCTUnwrap(onlyRow)
    XCTAssertEqual(row.categoryID, food)
    XCTAssertEqual(row.categorySource, .rule)
    XCTAssertEqual(row.appliedRuleID, rule.id)
  }

  // MARK: - Manual wins, permanently

  func testAManualCategorySurvivesASubsequentRulePass() async throws {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let manual = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: shopping,
      categorySource: .manual)
    let store = FakePipelineStore(rows: [manual], rules: [rule])
    let pipeline = await Fixture.pipeline(store: store)

    let result = try await pipeline.reapplyRules()

    XCTAssertEqual(result.recategorized, 0)
    let after = await store.row(manual.id)
    XCTAssertEqual(after?.categoryID, shopping, "a manual category is never overwritten by a rule")
    XCTAssertEqual(after?.categorySource, .manual)
  }

  func testAManualCategorySurvivesAMergeFromAnotherSource() async throws {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let draft = Fixture.draft(description: "SWIGGY ORDER", source: .email, externalID: "uid-1")
    let manual = Fixture.row(from: draft, categoryID: shopping, categorySource: .manual)
    let store = FakePipelineStore(rows: [manual], rules: [rule])
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest([
      Fixture.draft(description: "SWIGGY ORDER", source: .file, externalID: "REF-9")
    ])

    let count = await store.rowCount
    XCTAssertEqual(count, 1)
    let after = await store.row(manual.id)
    XCTAssertEqual(after?.categoryID, shopping)
    XCTAssertEqual(after?.categorySource, .manual)
    XCTAssertEqual(after?.mergedCount, 2)
  }

  // MARK: - Retroactive re-apply

  func testANewRuleIsRetroactiveAcrossTheLedgerWithoutAReImport() async throws {
    let uncategorized = Fixture.row(from: Fixture.draft(description: "SWIGGY ORDER"))
    let unrelated = Fixture.row(
      from: Fixture.draft(description: "IRCTC TICKET", amountMinor: 1_240_00))
    let store = FakePipelineStore(rows: [uncategorized, unrelated])
    let pipeline = await Fixture.pipeline(store: store)

    await store.setRules([Fixture.rule(pattern: "*SWIGGY*", categoryID: food)])
    let result = try await pipeline.reapplyRules()

    XCTAssertEqual(result.matched, 1)
    XCTAssertEqual(result.recategorized, 1)

    let hit = await store.row(uncategorized.id)
    XCTAssertEqual(hit?.categoryID, food)
    let miss = await store.row(unrelated.id)
    XCTAssertNil(miss?.categoryID)
  }

  func testAHigherPriorityRuleOverridesAnExistingRuleAssignment() async throws {
    let oldRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: shopping,
      categorySource: .rule,
      appliedRuleID: oldRule.id)
    let newRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1)
    let store = FakePipelineStore(rows: [row], rules: [oldRule, newRule])
    let pipeline = await Fixture.pipeline(store: store)

    let result = try await pipeline.reapplyRules()

    XCTAssertEqual(result.recategorized, 1)
    let after = await store.row(row.id)
    XCTAssertEqual(after?.categoryID, food)
    XCTAssertEqual(after?.appliedRuleID, newRule.id)
  }

  // MARK: - Delete

  func testRuleDeleteNullsProvenanceAndLeavesTheCategoryUntouched() async throws {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: food,
      categorySource: .rule,
      appliedRuleID: rule.id)
    let store = FakePipelineStore(rows: [row], rules: [rule])
    let pipeline = await Fixture.pipeline(store: store)

    let cleared = try await pipeline.ruleDeleted(rule.id)

    XCTAssertEqual(cleared, 1)
    let after = await store.row(row.id)
    XCTAssertEqual(after?.categoryID, food, "user story 7: the category stays")
    XCTAssertEqual(after?.categorySource, .rule)
    XCTAssertNil(after?.appliedRuleID)
  }

  func testRuleDeleteDoesNotTouchRowsAssignedByOtherRules() async throws {
    let deleted = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let kept = Fixture.rule(pattern: "*IRCTC*", categoryID: travel)
    let other = Fixture.row(
      from: Fixture.draft(description: "IRCTC TICKET", amountMinor: 1_240_00),
      categoryID: travel,
      categorySource: .rule,
      appliedRuleID: kept.id)
    let store = FakePipelineStore(rows: [other], rules: [kept])
    let pipeline = await Fixture.pipeline(store: store)

    let cleared = try await pipeline.ruleDeleted(deleted.id)

    XCTAssertEqual(cleared, 0)
    let after = await store.row(other.id)
    XCTAssertEqual(after?.appliedRuleID, kept.id)
  }
}
