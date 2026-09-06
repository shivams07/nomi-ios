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
  //
  // `firstMatch` no longer sorts its input (U10) - the order is a property of
  // the rule set, not of the row being tested, so it is computed once per pass
  // by the caller. These tests therefore call `precedenceOrdered` explicitly,
  // which is where the guarantee they are about now lives.

  func testLowerPriorityWinsAndEvaluationStopsAtTheFirstMatch() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5),
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1),
    ])
    let match = RuleEngine.firstMatch(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)
    XCTAssertEqual(match?.categoryID, food)
  }

  func testUnderEqualPriorityTheOlderRuleWinsRegardlessOfFetchOrder() {
    let older = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: food, priority: 0, createdAt: "2026-01-01")
    let newer = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: shopping, priority: 0, createdAt: "2026-06-01")

    for ordering in [[older, newer], [newer, older]] {
      let match = RuleEngine.firstMatch(
        normalizedDescription: "SWIGGY ORDER", in: RuleEngine.precedenceOrdered(ordering))
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
      RuleEngine.firstMatch(
        normalizedDescription: "SWIGGY ORDER", in: RuleEngine.precedenceOrdered($0))?.id
    }

    XCTAssertEqual(winners.count, permutations.count)
    XCTAssertEqual(Set(winners).count, 1, "the same rule must win from every fetch order")
    XCTAssertEqual(winners[0], [a, b, c].map(\.id).min(by: { $0.uuidString < $1.uuidString }))
  }

  func testDisabledRulesNeverMatch() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 0, isEnabled: false)
    ])
    XCTAssertNil(RuleEngine.firstMatch(normalizedDescription: "SWIGGY ORDER", in: rules))
  }

  // MARK: - The case bug

  /// `normalizedDescription` is uppercased by `normalizeDescription`,
  /// `globMatches` is case-sensitive, and nothing uppercased what the user
  /// typed. So a rule typed `*swiggy*` matched nothing, ever - no error, no
  /// warning, and a preview count of zero that reads as "this pattern is
  /// wrong" rather than "this app ignores lowercase". FAILS on `main`.
  func testALowercasePatternMatchesTheUppercasedNarration() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*swiggy*", categoryID: food)
    ])

    let match = RuleEngine.firstMatch(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)

    XCTAssertEqual(match?.categoryID, food)
  }

  func testMixedCaseAndUppercasePatternsBothStillMatch() {
    for pattern in ["*SWIGGY*", "*Swiggy*", "*sWiGgY*"] {
      let rules = RuleEngine.precedenceOrdered([
        Fixture.rule(pattern: pattern, categoryID: food)
      ])
      XCTAssertEqual(
        RuleEngine.firstMatch(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)?.categoryID,
        food, pattern)
    }
  }

  /// Uppercasing the pattern must not make a non-matching pattern match.
  func testUppercasingDoesNotWidenWhatAPatternMatches() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*zomato*", categoryID: food)
    ])
    XCTAssertNil(RuleEngine.firstMatch(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules))
  }

  // MARK: - B5: the rule set is ordered once per pass, not once per row

  func testFirstMatchDoesNotSortItsInput() {
    // Deliberately out of precedence order. `firstMatch` takes what it is
    // given, so the higher-priority rule wins purely by position - which is
    // the whole reason every caller in the repo now orders first.
    let unordered = [
      Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5),
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1),
    ]
    XCTAssertEqual(
      RuleEngine.firstMatch(normalizedDescription: "SWIGGY ORDER", in: unordered)?.categoryID,
      shopping)
    XCTAssertEqual(
      RuleEngine.firstMatch(
        normalizedDescription: "SWIGGY ORDER", in: RuleEngine.precedenceOrdered(unordered)
      )?.categoryID,
      food)
  }

  /// The cost B5 is about, measured rather than asserted in a comment.
  ///
  /// `firstMatch` used to sort internally and `apply` called `firstMatch`, so
  /// a reapply over N rows ordered the rule set 2N times to answer the same
  /// question N times. Both shapes return the same answer, so the only way to
  /// see the difference from outside is to count.
  func testAHundredRowReapplyOrdersTheRuleSetOnce() async throws {
    let rules = (0..<8).map {
      Fixture.rule(pattern: "*MERCHANT\($0)*", categoryID: food, priority: $0)
    }
    let rows = (0..<100).map { index in
      Fixture.row(
        from: Fixture.draft(
          description: "UPI/PM/MERCHANT\(index % 8)/X", externalID: "uid-\(index)"),
        createdAt: "2026-08-20 10:00")
    }
    let store = FakePipelineStore(rows: rows, rules: rules)
    let pipeline = await Fixture.pipeline(store: store)

    RuleEngine.orderingCount = 0
    _ = try await pipeline.reapplyRules()

    XCTAssertEqual(
      RuleEngine.orderingCount, 1,
      "once for the pass - it was 200 for these rows before B5")
  }

  /// And the cheaper pass still gets the same answer, row by row.
  func testTheCheaperPassAssignsExactlyWhatAnOrderedRuleSetWould() async throws {
    let rules = (0..<8).map {
      Fixture.rule(pattern: "*MERCHANT\($0)*", categoryID: food, priority: $0)
    }
    let rows = (0..<40).map { index in
      Fixture.row(
        from: Fixture.draft(
          description: "UPI/PM/MERCHANT\(index % 8)/X", externalID: "uid-\(index)"),
        createdAt: "2026-08-20 10:00")
    }
    let store = FakePipelineStore(rows: rows, rules: rules)
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.reapplyRules()

    let ordered = RuleEngine.precedenceOrdered(rules)
    for row in await store.allRows {
      let expected = RuleEngine.firstMatch(
        normalizedDescription: row.normalizedDescription, in: ordered)
      XCTAssertEqual(row.appliedRuleID, expected?.id, row.normalizedDescription)
    }
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
