import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// Rule precedence, and what `RuleEngine` does to a row on ingest, on a
/// retroactive pass and on rule delete.
///
/// The retroactive and delete cases used to be driven through the pipeline's
/// own `reapplyRules` and `ruleDeleted` passes, which nothing in the app
/// called (L9) and which are gone. `SwiftDataRuleStore` runs the retroactive
/// pass itself, through the same `RuleEngine.apply`. The semantics are pure, so
/// they are pinned here against `RuleEngine` directly; ingest, the one rule
/// pass the pipeline still runs, keeps its own tests.
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
    let match = RuleEngine.firstMatchIgnoringScope(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)
    XCTAssertEqual(match?.categoryID, food)
  }

  func testUnderEqualPriorityTheOlderRuleWinsRegardlessOfFetchOrder() {
    let older = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: food, priority: 0, createdAt: "2026-01-01")
    let newer = Fixture.rule(
      pattern: "*SWIGGY*", categoryID: shopping, priority: 0, createdAt: "2026-06-01")

    for ordering in [[older, newer], [newer, older]] {
      let match = RuleEngine.firstMatchIgnoringScope(
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
      RuleEngine.firstMatchIgnoringScope(
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
    XCTAssertNil(RuleEngine.firstMatchIgnoringScope(normalizedDescription: "SWIGGY ORDER", in: rules))
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

    let match = RuleEngine.firstMatchIgnoringScope(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)

    XCTAssertEqual(match?.categoryID, food)
  }

  func testMixedCaseAndUppercasePatternsBothStillMatch() {
    for pattern in ["*SWIGGY*", "*Swiggy*", "*sWiGgY*"] {
      let rules = RuleEngine.precedenceOrdered([
        Fixture.rule(pattern: pattern, categoryID: food)
      ])
      XCTAssertEqual(
        RuleEngine.firstMatchIgnoringScope(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules)?.categoryID,
        food, pattern)
    }
  }

  /// Uppercasing the pattern must not make a non-matching pattern match.
  func testUppercasingDoesNotWidenWhatAPatternMatches() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*zomato*", categoryID: food)
    ])
    XCTAssertNil(RuleEngine.firstMatchIgnoringScope(normalizedDescription: "UPI/PM//SWIGGY/HDFC", in: rules))
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
      RuleEngine.firstMatchIgnoringScope(normalizedDescription: "SWIGGY ORDER", in: unordered)?.categoryID,
      shopping)
    XCTAssertEqual(
      RuleEngine.firstMatchIgnoringScope(
        normalizedDescription: "SWIGGY ORDER", in: RuleEngine.precedenceOrdered(unordered)
      )?.categoryID,
      food)
  }

  /// Eight merchant rules and a catch-all that also matches every row but
  /// loses on priority, so the winner depends on precedence, not on which rule
  /// happens to match.
  ///
  /// Letters, not `MERCHANT\(n)`: `normalizeDescription` strips digit runs, so
  /// a numbered merchant normalises to the same text as every other and no
  /// numbered pattern can match it. The retroactive-pass version of these two
  /// tests used numbered merchants, and every row it checked was `nil == nil`.
  private static let merchants = ["ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL"]

  private func merchantRules() -> [RuleSnapshot] {
    var rules: [RuleSnapshot] = []
    for (index, name) in Self.merchants.enumerated() {
      rules.append(Fixture.rule(pattern: "*\(name)*", categoryID: food, priority: index))
    }
    rules.append(Fixture.rule(pattern: "*UPI*", categoryID: shopping, priority: 100))
    return rules
  }

  private func merchantDrafts(count: Int) -> [TransactionDraft] {
    (0..<count).map { index in
      // A distinct amount per draft, so no two drafts in the batch merge.
      Fixture.draft(
        description: "UPI/PM/\(Self.merchants[index % Self.merchants.count])/X",
        amountMinor: 1_000 + index,
        externalID: "uid-\(index)")
    }
  }

  /// The cost B5 is about, measured rather than asserted in a comment.
  ///
  /// `firstMatch` used to sort internally and `apply` called `firstMatch`, so
  /// a batch of N drafts ordered the rule set 2N times to answer the same
  /// question N times. Both shapes return the same answer, so the only way to
  /// see the difference from outside is to count.
  func testAHundredDraftIngestOrdersTheRuleSetOnce() async throws {
    let store = FakePipelineStore(rules: merchantRules())
    let pipeline = await Fixture.pipeline(store: store)

    RuleEngine.orderingCount = 0
    let result = try await pipeline.ingest(merchantDrafts(count: 100))

    XCTAssertEqual(result.created, 100)
    XCTAssertEqual(
      RuleEngine.orderingCount, 1,
      "once for the batch - it would be 200 for these drafts before B5")
  }

  /// And the cheaper pass still gets the same answer, row by row.
  func testTheCheaperPassAssignsExactlyWhatAnOrderedRuleSetWould() async throws {
    let rules = merchantRules()
    let store = FakePipelineStore(rules: rules)
    let pipeline = await Fixture.pipeline(store: store)

    _ = try await pipeline.ingest(merchantDrafts(count: 40))

    let ordered = RuleEngine.precedenceOrdered(rules)
    let rows = await store.allRows
    XCTAssertEqual(rows.count, 40)
    for row in rows {
      let expected = RuleEngine.firstMatchIgnoringScope(
        normalizedDescription: row.normalizedDescription, in: ordered)
      XCTAssertNotNil(expected, "every row must match something, or this compares nil to nil")
      XCTAssertEqual(row.appliedRuleID, expected?.id, row.normalizedDescription)
      XCTAssertEqual(row.categoryID, food, "the merchant rule beats the catch-all")
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

  func testAManualCategorySurvivesARulePass() {
    let rules = RuleEngine.precedenceOrdered([Fixture.rule(pattern: "*SWIGGY*", categoryID: food)])
    let manual = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: shopping,
      categorySource: .manual)

    XCTAssertNil(
      RuleEngine.apply(rules, to: manual), "a manual category is never overwritten by a rule")
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

  // MARK: - Retroactive

  func testANewRuleCategorizesAnExistingRowAndLeavesAnUnmatchedOneAlone() {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let rules = RuleEngine.precedenceOrdered([rule])
    let uncategorized = Fixture.row(from: Fixture.draft(description: "SWIGGY ORDER"))
    let unrelated = Fixture.row(
      from: Fixture.draft(description: "IRCTC TICKET", amountMinor: 1_240_00))

    let hit = RuleEngine.apply(rules, to: uncategorized)
    XCTAssertEqual(hit?.categoryID, food)
    XCTAssertEqual(hit?.categorySource, .rule)
    XCTAssertEqual(hit?.appliedRuleID, rule.id)

    XCTAssertNil(RuleEngine.apply(rules, to: unrelated))
  }

  func testAHigherPriorityRuleOverridesAnExistingRuleAssignment() {
    let oldRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: shopping,
      categorySource: .rule,
      appliedRuleID: oldRule.id)
    let newRule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1)

    let next = RuleEngine.apply(RuleEngine.precedenceOrdered([oldRule, newRule]), to: row)

    XCTAssertEqual(next?.categoryID, food)
    XCTAssertEqual(next?.appliedRuleID, newRule.id)
  }

  /// Re-running the rule that already assigned a row is not a change, so a
  /// pass over an unchanged ledger writes nothing.
  func testReapplyingTheRuleThatAlreadyAssignedARowIsANoOp() {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: food,
      categorySource: .rule,
      appliedRuleID: rule.id)

    XCTAssertNil(RuleEngine.apply(RuleEngine.precedenceOrdered([rule]), to: row))
  }

  // MARK: - Delete

  func testRuleDeleteNullsProvenanceAndLeavesTheCategoryUntouched() throws {
    let rule = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let row = Fixture.row(
      from: Fixture.draft(description: "SWIGGY ORDER"),
      categoryID: food,
      categorySource: .rule,
      appliedRuleID: rule.id)

    let after = try XCTUnwrap(RuleEngine.clearingProvenance(of: rule.id, from: row))

    XCTAssertEqual(after.categoryID, food, "user story 7: the category stays")
    XCTAssertEqual(after.categorySource, .rule)
    XCTAssertNil(after.appliedRuleID)
  }

  func testRuleDeleteDoesNotTouchRowsAssignedByOtherRules() {
    let deleted = Fixture.rule(pattern: "*SWIGGY*", categoryID: food)
    let kept = Fixture.rule(pattern: "*IRCTC*", categoryID: travel)
    let other = Fixture.row(
      from: Fixture.draft(description: "IRCTC TICKET", amountMinor: 1_240_00),
      categoryID: travel,
      categorySource: .rule,
      appliedRuleID: kept.id)

    XCTAssertNil(RuleEngine.clearingProvenance(of: deleted.id, from: other))
  }

  // MARK: - Scope (W2-5)
  //
  // `Fixture.rule` cannot carry a scope — `PipelineTestSupport` belongs to
  // another unit — so these build their `RuleSnapshot`s here. Every one of them
  // uses the *same pattern* as the row it is tested against, so a failure can
  // only be the scope: if the pattern were doing the work the test would pass
  // for the wrong reason.

  private func scoped(
    _ scope: RuleScope,
    pattern: String = "*SWIGGY*",
    categoryID: UUID? = nil,
    priority: Int = 0
  ) -> RuleSnapshot {
    RuleSnapshot(
      id: UUID(),
      pattern: pattern,
      categoryID: categoryID ?? food,
      priority: priority,
      isEnabled: true,
      scope: scope,
      createdAt: Fixture.date("2026-01-01")
    )
  }

  private func swiggyRow(
    direction: Direction = .debit,
    amountMinor: Int = 45_900,
    accountID: UUID? = nil
  ) -> TransactionSnapshot {
    Fixture.row(
      from: Fixture.draft(
        description: "UPI/P2M/412345678901/SWIGGY/HDFC/Order",
        amountMinor: amountMinor,
        direction: direction,
        accountID: accountID))
  }

  func testACreditScopedRuleDoesNotMatchADebitWithTheSamePattern() {
    let rule = scoped(RuleScope(direction: .credit))

    XCTAssertNil(
      RuleEngine.firstMatch(row: swiggyRow(direction: .debit), in: [rule]),
      "the pattern matches; the direction does not")
    XCTAssertEqual(
      RuleEngine.firstMatch(row: swiggyRow(direction: .credit), in: [rule])?.id, rule.id,
      "and the same rule must still match the direction it was scoped to")
  }

  func testAnAmountRangeExcludesRowsOutsideItAndIncludesBothBounds() {
    let rule = scoped(RuleScope(minAmountMinor: 10_000, maxAmountMinor: 50_000))

    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 9_999), in: [rule]))
    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 50_001), in: [rule]))
    XCTAssertNotNil(
      RuleEngine.firstMatch(row: swiggyRow(amountMinor: 10_000), in: [rule]), "inclusive low")
    XCTAssertNotNil(
      RuleEngine.firstMatch(row: swiggyRow(amountMinor: 50_000), in: [rule]), "inclusive high")
  }

  func testAHalfOpenRangeBoundsOnlyTheEndItSets() {
    let atLeast = scoped(RuleScope(minAmountMinor: 100_000))
    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 99_999), in: [atLeast]))
    XCTAssertNotNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 9_999_999), in: [atLeast]))

    let atMost = scoped(RuleScope(maxAmountMinor: 100_000))
    XCTAssertNotNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 1), in: [atMost]))
    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(amountMinor: 100_001), in: [atMost]))
  }

  /// An unowned row is admitted only by a rule that did not ask for an account.
  func testAnAccountScopedRuleSkipsAnotherAccountAndAnUnownedRow() {
    let hdfc = UUID()
    let icici = UUID()
    let rule = scoped(RuleScope(accountID: hdfc))

    XCTAssertEqual(
      RuleEngine.firstMatch(row: swiggyRow(accountID: hdfc), in: [rule])?.id, rule.id)
    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(accountID: icici), in: [rule]))
    XCTAssertNil(
      RuleEngine.firstMatch(row: swiggyRow(accountID: nil), in: [rule]),
      "a row that belongs to no account is not in the account the user picked")
  }

  /// Every condition is an AND: one failing field is enough, and satisfying
  /// three of four is not a match.
  func testEveryFieldOfAScopeMustBeSatisfiedAtOnce() {
    let account = UUID()
    let rule = scoped(
      RuleScope(
        direction: .debit, accountID: account, minAmountMinor: 10_000, maxAmountMinor: 50_000))

    XCTAssertNotNil(
      RuleEngine.firstMatch(
        row: swiggyRow(direction: .debit, amountMinor: 20_000, accountID: account), in: [rule]))
    XCTAssertNil(
      RuleEngine.firstMatch(
        row: swiggyRow(direction: .credit, amountMinor: 20_000, accountID: account), in: [rule]),
      "direction alone")
    XCTAssertNil(
      RuleEngine.firstMatch(
        row: swiggyRow(direction: .debit, amountMinor: 80_000, accountID: account), in: [rule]),
      "amount alone")
    XCTAssertNil(
      RuleEngine.firstMatch(
        row: swiggyRow(direction: .debit, amountMinor: 20_000, accountID: UUID()), in: [rule]),
      "account alone")
  }

  /// `.any` behaves as today: the same answer the pattern-only overload gives,
  /// on a rule set that has no scopes in it.
  func testAnUnscopedRuleSetAnswersExactlyWhatItAnsweredBeforeScoping() {
    let rules = RuleEngine.precedenceOrdered([
      Fixture.rule(pattern: "*SWIGGY*", categoryID: shopping, priority: 5),
      Fixture.rule(pattern: "*SWIGGY*", categoryID: food, priority: 1),
    ])
    let row = swiggyRow()

    XCTAssertTrue(rules.allSatisfy { $0.scope.isAny }, "Fixture.rule must still build unscoped rules")
    XCTAssertEqual(RuleEngine.firstMatch(row: row, in: rules)?.categoryID, food)
    XCTAssertEqual(
      RuleEngine.firstMatch(row: row, in: rules)?.id,
      RuleEngine.firstMatchIgnoringScope(normalizedDescription: row.normalizedDescription, in: rules)?.id)
  }

  /// Precedence does not stop at a rule the scope rejects — it passes over it.
  ///
  /// The scoped rule is *first* in precedence and would win on pattern alone,
  /// so a `firstMatch` that treated a rejected scope as "no match at all" would
  /// return nil here rather than the catch-all.
  func testEvaluationContinuesPastARuleWhoseScopeRejectsTheRow() {
    let rules = RuleEngine.precedenceOrdered([
      scoped(RuleScope(direction: .credit), categoryID: shopping, priority: 0),
      scoped(.any, categoryID: food, priority: 1),
    ])

    let match = RuleEngine.firstMatch(row: swiggyRow(direction: .debit), in: rules)
    XCTAssertEqual(match?.categoryID, food, "the credit-only rule is skipped, not fatal")
  }

  /// `apply` inherits the scope, since it is the path ingest and the
  /// retroactive pass both take.
  func testApplyLeavesARowAScopedRuleDoesNotAdmitUntouched() {
    let rule = scoped(RuleScope(minAmountMinor: 1_000_000))
    let row = swiggyRow(amountMinor: 45_900)

    XCTAssertNil(RuleEngine.apply([rule], to: row))
    XCTAssertNotNil(
      RuleEngine.apply([scoped(.any)], to: row),
      "and the same row with the same pattern is assigned when the scope admits it")
  }

  /// `firstMatchIgnoringScope` declines every scoped rule rather than guessing
  /// at a condition it has no facts for.
  ///
  /// It has no production caller — the suggester moved to `firstMatch(row:)`
  /// with this unit — but the precedence tests above still use it, so what it
  /// does with a scoped rule has to be pinned rather than assumed.
  func testTheScopeIgnoringHelperNeverReturnsAScopedRule() {
    let scopedRule = scoped(RuleScope(direction: .debit), categoryID: shopping, priority: 0)
    let unscopedRule = scoped(.any, categoryID: food, priority: 1)
    let description = swiggyRow().normalizedDescription

    XCTAssertNil(RuleEngine.firstMatchIgnoringScope(normalizedDescription: description, in: [scopedRule]))
    XCTAssertEqual(
      RuleEngine.firstMatchIgnoringScope(
        normalizedDescription: description,
        in: RuleEngine.precedenceOrdered([scopedRule, unscopedRule]))?.categoryID,
      food,
      "it falls through to the unscoped rule rather than answering nothing")
  }

  func testADisabledRuleIsSkippedWhateverItsScopeSays() {
    let rule = RuleSnapshot(
      id: UUID(), pattern: "*SWIGGY*", categoryID: food, priority: 0, isEnabled: false,
      scope: .any, createdAt: Fixture.date("2026-01-01"))

    XCTAssertNil(RuleEngine.firstMatch(row: swiggyRow(), in: [rule]))
  }
}
