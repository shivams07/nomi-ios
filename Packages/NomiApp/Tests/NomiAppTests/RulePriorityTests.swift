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

    try store.create(pattern: "*SWIGGY*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*SWIGGY*", in: context))
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

    try store.create(pattern: "*SWIGGY*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*SWIGGY*", in: context))
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

    try store.create(pattern: "*SWIGGY*", categoryID: UUID())

    let created = try XCTUnwrap(rule(pattern: "*SWIGGY*", in: context))
    XCTAssertLessThan(
      created.priority, 0,
      "a band-based fix passes every other test here and fails this one")
  }

  func testTheFirstRuleInAnEmptyStoreIsAccepted() throws {
    let (store, context) = try makeStore()

    try store.create(pattern: "*SWIGGY*", categoryID: UUID())

    XCTAssertEqual(try XCTUnwrap(rule(pattern: "*SWIGGY*", in: context)).priority, 0)
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

    try fake.create(pattern: "*SWIGGY*", categoryID: UUID())

    let created = try XCTUnwrap(fake.rules.first { $0.pattern == "*SWIGGY*" })
    let others = fake.rules.filter { $0.pattern != "*SWIGGY*" }.map(\.priority)
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
    try store.create(pattern: "*SWIGGY*", categoryID: UUID())
    let realRule = try XCTUnwrap(rule(pattern: "*SWIGGY*", in: context))
    let real = realRule.priority

    let fake = FakeRuleStore(
      rules: starting.map { Rule(pattern: "*\($0)*", categoryID: UUID(), priority: $0) },
      matchPool: [])
    try fake.create(pattern: "*SWIGGY*", categoryID: UUID())
    let fakeRule = try XCTUnwrap(fake.rules.first { $0.pattern == "*SWIGGY*" })
    let faked = fakeRule.priority

    XCTAssertEqual(real, faked, "the preview stack must not demonstrate the old behaviour")
  }

  // MARK: -

  /// A fresh container per test.
  ///
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
}
