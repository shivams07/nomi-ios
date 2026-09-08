import Foundation
import NomiCore
import NomiIngest
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// A rule the user just wrote must beat every rule that was already there.
///
/// `RuleEngine.precedenceOrdered` sorts ascending and `firstMatch` stops at the
/// first hit, so **lower `priority` wins**. Both stores created new rules at the
/// *back* of that order — `max() + 1` in the real one, `rules.count` in the fake
/// — which means every rule the user writes loses to everything already present.
///
/// That was invisible while the store shipped empty. `DefaultRuleSeed` put 47
/// rules in it, and the user's first rule now loses to all of them.
@MainActor
final class RulePriorityTests: XCTestCase {

  // MARK: - The real store

  /// The invariant, stated once: after `create`, the new rule outranks
  /// everything that was there before it.
  func testANewRuleOutranksEveryRuleThatWasAlreadyThere() throws {
    let (store, context) = try makeStore()
    try seedRules(in: context, priorities: [0, 1, 2])

    try store.create(pattern: "*MYOWNRULE*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*MYOWNRULE*", in: context))
    XCTAssertLessThan(
      created.priority, 0,
      "a new rule must sort ahead of priorities \(priorities(in: context))")
  }

  /// The case the seed actually creates. Not a stand-in — this applies the real
  /// `DefaultRuleSeed` and then writes a rule the way `RulesScreen`'s + button
  /// does.
  func testAUserRuleOutranksTheWholeDefaultRuleSeed() throws {
    let (store, context) = try makeStore()
    try DefaultRuleSeed.apply(in: context)

    let seeded = try context.fetch(FetchDescriptor<Rule>())
    XCTAssertEqual(seeded.count, DefaultRuleSeed.specs.count, "the seed is the fixture here")

    // The pattern must be one the seed does not already carry. `*SWIGGY*` does
    // — it is the seed's first merchant rule — so looking the created rule up
    // by pattern would find the seeded one instead, and the test would report
    // on a row it did not create.
    XCTAssertFalse(
      DefaultRuleSeed.specs.map(\.pattern).contains("*MYOWNRULE*"),
      "pick a pattern the seed cannot supply")

    try store.create(pattern: "*MYOWNRULE*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*MYOWNRULE*", in: context))
    let lowestSeeded = try XCTUnwrap(seeded.map(\.priority).min())
    XCTAssertLessThan(
      created.priority, lowestSeeded,
      "the user's own rule must win against every seeded one")
  }

  /// Front-insertion twice. The second rule has to go ahead of a set whose
  /// minimum is already negative — the case a fix that only special-cased "no
  /// rules yet" or "priorities start at zero" would get wrong.
  func testFrontInsertionKeepsWorkingOnceThePrioritiesAreNegative() throws {
    let (store, context) = try makeStore()
    try seedRules(in: context, priorities: [0, 1, 2])

    try store.create(pattern: "*FIRST*", categoryID: UUID())
    let first = try XCTUnwrap(rule(pattern: "*FIRST*", in: context))
    XCTAssertLessThan(first.priority, 0)

    try store.create(pattern: "*SECOND*", categoryID: UUID())
    let second = try XCTUnwrap(rule(pattern: "*SECOND*", in: context))

    XCTAssertLessThan(
      second.priority, first.priority,
      "the newest rule wins, and the previous front-insert must not block it")
  }

  /// **The test that rules out a reserved priority band.**
  ///
  /// Giving the seed a high band and the user a low one looks equivalent and is
  /// not: `reorder` rewrites `priority` to the array index across *every* rule
  /// wholesale, so one drag-to-reorder gesture collapses the band and the bug
  /// comes back with nothing to show for it. Front-insertion is defined
  /// relative to whatever `reorder` last wrote, so it survives.
  func testTheInvariantSurvivesAReorderThatRewritesEveryPriority() throws {
    let (store, context) = try makeStore()
    try seedRules(in: context, priorities: [1_000_000, 1_000_001, 1_000_002])

    // Exactly what a drag in RulesScreen does: priorities become 0..<n.
    let existing = try context.fetch(FetchDescriptor<Rule>())
    try store.reorder(existing.map(\.id))
    XCTAssertEqual(priorities(in: context).sorted(), [0, 1, 2], "reorder flattened the band")

    try store.create(pattern: "*MYOWNRULE*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*MYOWNRULE*", in: context))
    XCTAssertLessThan(
      created.priority, 0,
      "a band-based fix passes every other test here and fails this one")
  }

  func testTheFirstRuleInAnEmptyStoreIsAccepted() throws {
    let (store, context) = try makeStore()

    try store.create(pattern: "*MYOWNRULE*", categoryID: UUID())

    XCTAssertEqual(try XCTUnwrap(rule(pattern: "*MYOWNRULE*", in: context)).priority, 0)
  }

  // MARK: - The fake store must agree

  /// `FakeRuleStore` carried the identical bug in a different spelling
  /// (`priority: rules.count`). Left alone it would drift from production, and
  /// every preview and every screen built against it would demonstrate the
  /// behaviour that was just fixed.
  ///
  /// `NomiPreview` is reachable here through `NomiApp` -> `NomiUI` ->
  /// `NomiPreview`, which is what lets one test hold both stores to one rule.
  func testFakeRuleStoreFrontInsertsTheSameWayTheRealOneDoes() throws {
    let fake = FakeRuleStore(rules: [
      Rule(pattern: "*A*", categoryID: UUID(), priority: 0),
      Rule(pattern: "*B*", categoryID: UUID(), priority: 1),
    ], matchPool: [])

    try fake.create(pattern: "*MYOWNRULE*", categoryID: UUID())

    let created = try XCTUnwrap(fake.rules.first { $0.pattern == "*MYOWNRULE*" })
    let others = fake.rules.filter { $0.pattern != "*MYOWNRULE*" }.map(\.priority)
    let lowestOther = try XCTUnwrap(others.min())
    XCTAssertLessThan(created.priority, lowestOther)
  }

  /// The agreement itself, rather than two tests that happen to pass. Both
  /// stores start from the same priorities and must produce the same answer to
  /// "where does a new rule go".
  func testBothStoresPlaceANewRuleAtTheSamePriority() throws {
    let starting = [0, 1, 2]

    let (store, context) = try makeStore()
    try seedRules(in: context, priorities: starting)
    try store.create(pattern: "*MYOWNRULE*", categoryID: UUID())
    let realRule = try XCTUnwrap(rule(pattern: "*MYOWNRULE*", in: context))
    let real = realRule.priority

    let fake = FakeRuleStore(
      rules: starting.map { Rule(pattern: "*\($0)*", categoryID: UUID(), priority: $0) },
      matchPool: [])
    try fake.create(pattern: "*MYOWNRULE*", categoryID: UUID())
    let fakeRule = try XCTUnwrap(fake.rules.first { $0.pattern == "*MYOWNRULE*" })
    let faked = fakeRule.priority

    XCTAssertEqual(real, faked, "the preview stack must not demonstrate the old behaviour")
  }

  // MARK: -

  /// A fresh container per test.
  ///
  // MARK: - B5: the narrowed fetch answers what the full scan answered

  /// `preview` now filters the fetch on the pattern's literal prefix instead of
  /// materialising every row. The only thing that matters is that it returns
  /// the same number — a narrowing that loses a match is a preview that lies
  /// about what a rule will do.
  ///
  /// Both paths are covered: `UPI/PM*` has a literal prefix and takes the
  /// narrowed fetch, `*SWIGGY*` has none and falls back to the full scan.
  func testPreviewMatchesAFullScanOnBothThePrefixedAndUnprefixedPaths() throws {
    let (store, context) = try makeStore()
    try seedTransactions(in: context)

    for pattern in ["UPI/PM*", "*SWIGGY*", "UPI/PM*SWIGGY*", "*", "NOTHINGLIKETHIS*"] {
      let all = try context.fetch(FetchDescriptor<Transaction>())
      let expected = all.filter {
        globMatches(pattern: pattern.uppercased(), value: $0.normalizedDescription)
      }.count

      XCTAssertEqual(try store.preview(pattern: pattern), expected, pattern)
    }
  }

  /// A lowercase pattern previewed as zero, which reads as "this pattern is
  /// wrong" rather than "this app ignores lowercase". FAILS on `main`.
  func testPreviewCountsALowercasePatternTheSameAsItsUppercaseForm() throws {
    let (store, context) = try makeStore()
    try seedTransactions(in: context)

    let upper = try store.preview(pattern: "*SWIGGY*")
    XCTAssertGreaterThan(upper, 0, "the fixture must actually contain a match")
    XCTAssertEqual(try store.preview(pattern: "*swiggy*"), upper)
    XCTAssertEqual(try store.preview(pattern: "*Swiggy*"), upper)
  }

  /// `preview` counts manually-categorised rows too — the user is asking what
  /// a pattern hits, and silently excluding their own rows would read as the
  /// pattern being wrong. The narrowed fetch must not quietly change that.
  func testPreviewStillCountsManuallyCategorisedRows() throws {
    let (store, context) = try makeStore()
    context.insert(
      Transaction(
        descriptionText: "UPI/PM/SWIGGY", normalizedDescription: "UPI/PM/SWIGGY",
        categorySourceRaw: CategorySource.manual.rawValue, dedupeKey: "m1"))
    try context.save()

    XCTAssertEqual(try store.preview(pattern: "*SWIGGY*"), 1)
    XCTAssertEqual(try store.preview(pattern: "UPI/PM*"), 1)
  }

  private func seedTransactions(in context: ModelContext) throws {
    let narrations = [
      "UPI/PM/SWIGGY/HDFC",
      "UPI/PM/ZOMATO/HDFC",
      "UPI/PP/SWIGGY/ICICI",
      "NEFT SALARY",
      "POS SWIGGY INSTAMART",
    ]
    for (index, narration) in narrations.enumerated() {
      context.insert(
        Transaction(
          descriptionText: narration,
          normalizedDescription: narration,
          dedupeKey: "k\(index)"))
    }
    try context.save()
  }

  // MARK: -

  /// Deliberately not `InMemoryModelContainer.shared`: these tests are about
  /// what `create` does given a particular set of existing priorities, so one
  /// test's rules leaking into the next would make the assertions meaningless.
  /// A `ModelContainer` under `swift test` is fine in XCTest and traps under
  /// swift-testing — see `InMemoryModelContainer` — which is why this is XCTest.
  private func makeStore() throws -> (SwiftDataRuleStore, ModelContext) {
    let schema = Schema([
      Transaction.self, NomiCore.Category.self, Budget.self, BudgetAlertLog.self,
      Rule.self, Account.self, AccountBinding.self, ColumnMappingRecord.self,
    ])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    let context = container.mainContext
    let store = SwiftDataRuleStore(context: context, coordinator: WriteCoordinator(cache: InsightsCache()))
    return (store, context)
  }

  private func seedRules(in context: ModelContext, priorities: [Int]) throws {
    for priority in priorities {
      context.insert(Rule(pattern: "*EXISTING\(priority)*", categoryID: UUID(), priority: priority))
    }
    try context.save()
  }

  private func rule(pattern: String, in context: ModelContext) throws -> Rule? {
    try context.fetch(FetchDescriptor<Rule>()).first { $0.pattern == pattern }
  }

  private func priorities(in context: ModelContext) -> [Int] {
    ((try? context.fetch(FetchDescriptor<Rule>())) ?? []).map(\.priority)
  }

  // MARK: - System rules, and turning a rule off (M2)

  /// A seeded rule refuses to be deleted, and is still there afterwards.
  ///
  /// The second half is the half worth asserting. A `delete` that threw *after*
  /// removing the row, or that removed it and threw on `save`, would satisfy
  /// "it throws" and still lose the rule.
  func testASystemRuleRefusesToBeDeletedAndSurvivesTheAttempt() throws {
    let (store, context) = try makeStore()
    let rule = Rule(pattern: "*BLINKIT*", categoryID: UUID(), priority: 0, isSystem: true)
    context.insert(rule)
    try context.save()

    XCTAssertThrowsError(try store.delete(rule.id)) { error in
      XCTAssertEqual(error as? RuleStoreError, .systemRuleCannotBeDeleted)
    }

    let survivors = try context.fetch(FetchDescriptor<Rule>())
    XCTAssertEqual(survivors.map(\.id), [rule.id], "the row must still be there")
  }

  /// The control. Without it, a `delete` that threw for *every* rule would pass
  /// the test above.
  func testARuleTheUserWroteStillDeletes() throws {
    let (store, context) = try makeStore()
    let rule = Rule(pattern: "*MYOWNRULE*", categoryID: UUID(), priority: 0)
    context.insert(rule)
    try context.save()

    try store.delete(rule.id)

    XCTAssertTrue(try context.fetch(FetchDescriptor<Rule>()).isEmpty)
  }

  /// Disabling stops the rule firing on the *next* entry, and re-enabling puts
  /// it back — through the real manual-add path, not through the engine
  /// directly, because `SwiftDataTransactionStore.add` is where a user's entry
  /// actually meets the rule set.
  ///
  /// The first `add` is not scene-setting. Without it a pattern that never
  /// matched anything would produce the same "not categorised" result and the
  /// test would pass while proving nothing.
  func testADisabledRuleStopsCategorisingNewEntriesAndReEnablingRestoresIt() throws {
    let (store, context) = try makeStore()
    let groceries = UUID()
    let rule = Rule(pattern: "*BLINKIT*", categoryID: groceries, priority: 0)
    context.insert(rule)
    try context.save()
    let transactions = SwiftDataTransactionStore(
      context: context, coordinator: WriteCoordinator(cache: InsightsCache()))

    let whileOn = try transactions.add(
      ManualTransactionDraft(amountMinor: 100, descriptionText: "BLINKIT ORDER"))
    XCTAssertEqual(whileOn.categoryID, groceries, "the rule must match before disabling proves anything")
    XCTAssertEqual(whileOn.appliedRuleID, rule.id)

    try store.setEnabled(rule.id, false)

    let whileOff = try transactions.add(
      ManualTransactionDraft(amountMinor: 200, descriptionText: "BLINKIT ORDER"))
    XCTAssertNil(whileOff.categoryID, "a disabled rule must not categorise a new entry")
    XCTAssertNil(whileOff.appliedRuleID)

    try store.setEnabled(rule.id, true)

    let backOn = try transactions.add(
      ManualTransactionDraft(amountMinor: 300, descriptionText: "BLINKIT ORDER"))
    XCTAssertEqual(backOn.categoryID, groceries, "re-enabling must restore it")
    XCTAssertEqual(backOn.appliedRuleID, rule.id)
  }

  /// **Disabling is not a retroactive undo.** The row the rule already
  /// categorised keeps its category, exactly as it does when the rule is
  /// deleted — spend must not move between categories as a side effect of a
  /// toggle.
  func testDisablingARuleLeavesRowsItAlreadyCategorisedAlone() throws {
    let (store, context) = try makeStore()
    let groceries = UUID()
    let rule = Rule(pattern: "*BLINKIT*", categoryID: groceries, priority: 0)
    context.insert(rule)
    try context.save()
    let transactions = SwiftDataTransactionStore(
      context: context, coordinator: WriteCoordinator(cache: InsightsCache()))

    let row = try transactions.add(
      ManualTransactionDraft(amountMinor: 100, descriptionText: "BLINKIT ORDER"))
    XCTAssertEqual(row.categoryID, groceries)

    try store.setEnabled(rule.id, false)

    XCTAssertEqual(row.categoryID, groceries, "an existing categorisation must survive the toggle")
    XCTAssertEqual(row.appliedRuleID, rule.id, "and so must its provenance")
  }

  /// The fake refuses a system rule too. Same reasoning as the front-insertion
  /// agreement above: a preview stack that deletes what production rejects
  /// demonstrates behaviour the app does not have.
  ///
  /// The two stores throw *different* error types — `NomiPreview` sits below
  /// `NomiApp` and cannot name `RuleStoreError` — so what is asserted is the
  /// shared half of the contract: it throws, and the rule is still there.
  func testFakeRuleStoreRefusesToDeleteASystemRuleTheSameWay() throws {
    let system = Rule(pattern: "*BLINKIT*", categoryID: UUID(), priority: 0, isSystem: true)
    let mine = Rule(pattern: "*MYOWNRULE*", categoryID: UUID(), priority: 1)
    let fake = FakeRuleStore(rules: [system, mine], matchPool: [])

    XCTAssertThrowsError(try fake.delete(system.id))
    XCTAssertEqual(fake.rules.map(\.id), [system.id, mine.id])

    try fake.delete(mine.id)
    XCTAssertEqual(fake.rules.map(\.id), [system.id])
  }

  func testFakeRuleStoreSetEnabledFlipsTheFlag() throws {
    let rule = Rule(pattern: "*BLINKIT*", categoryID: UUID(), priority: 0)
    let fake = FakeRuleStore(rules: [rule], matchPool: [])

    try fake.setEnabled(rule.id, false)
    XCTAssertFalse(try XCTUnwrap(fake.rules.first).isEnabled)

    try fake.setEnabled(rule.id, true)
    XCTAssertTrue(try XCTUnwrap(fake.rules.first).isEnabled)
  }
}
