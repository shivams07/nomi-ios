import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// UI refresh P3. The transaction sheet's suggestion: the user's own history for
/// the merchant, then the rule engine, and nothing at all for a row the user has
/// already decided.
///
/// Every nil case that could also be nil because the store is simply broken has
/// a control beside it: the same evidence, one fact changed, and a suggestion
/// comes back. Changing that fact and re-asking also proves there is no cache.
///
/// XCTest, not swift-testing, because it needs a real `ModelContainer` (see
/// `InMemoryModelContainer`'s note in NomiCore).
@MainActor
final class CategorySuggesterTests: XCTestCase {

  /// Fixed ids so the tie-break is decidable: `food` sorts before `shopping`.
  private let food = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
  private let shopping = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
  private let entertainment = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!
  private let bills = UUID(uuidString: "00000000-0000-0000-0000-0000000000A4")!

  // MARK: - nil cases

  /// (1) An uncategorised `.manual` row is a real state: `setCategory(_:to: nil)`
  /// stamps `.manual`. The user chose "no category" and is not second-guessed.
  func testAManualRowGetsNoSuggestionWhateverTheEvidence() throws {
    let (suggester, context) = try makeSuggester()
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    insertRule("*SWIGGY*", category: food, into: context)
    let manual = insertRow("SWIGGY", category: nil, source: .manual, into: context)
    let undecided = insertRow("SWIGGY", category: nil, source: .none, into: context)

    XCTAssertNil(try suggester.suggestion(for: manual.id))
    XCTAssertNotNil(
      try suggester.suggestion(for: undecided.id),
      "control: the same evidence does reach a row the user has not decided")
  }

  func testAMissingRowGetsNoSuggestion() throws {
    let (suggester, _) = try makeSuggester()

    XCTAssertNil(try suggester.suggestion(for: UUID()))
  }

  /// (5) The candidate is already the row's category, so there is nothing to
  /// apply.
  func testAHistoryCandidateEqualToTheCurrentCategoryIsNotSuggested() throws {
    let (suggester, context) = try makeSuggester()
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    let row = insertRow("SWIGGY", category: food, source: .rule, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))

    row.categoryID = nil
    row.categorySourceRaw = CategorySource.none.rawValue
    try context.save()
    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: food, reason: .merchantHistory(matches: 2)),
      "control: uncategorised, the same history is suggested")
  }

  /// (5), the case that happens most: ingest already applied this rule, so the
  /// rule agrees with the row.
  func testARuleThatAlreadyAppliedIsNotSuggestedAgain() throws {
    let (suggester, context) = try makeSuggester()
    insertRule("*NETFLIX*", category: entertainment, into: context)
    let row = insertRow("NETFLIX COM", category: entertainment, source: .rule, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))
  }

  /// History has an answer and it agrees with the row. A rule that disagrees is
  /// not offered in its place: history outranks rules even when it is the
  /// reason there is nothing to suggest.
  func testWhenHistoryAgreesWithTheRowADisagreeingRuleIsNotOfferedInstead() throws {
    let (suggester, context) = try makeSuggester()
    insertRule("*NETFLIX*", category: entertainment, into: context)
    insertRow("NETFLIX COM", category: bills, source: .manual, into: context)
    let row = insertRow("NETFLIX COM", category: bills, source: .rule, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))
  }

  /// (6)
  func testTheOnlyMatchingRuleBeingDisabledSuggestsNothing() throws {
    let (suggester, context) = try makeSuggester()
    let rule = insertRule("*NETFLIX*", category: entertainment, enabled: false, into: context)
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))

    rule.isEnabled = true
    try context.save()
    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: entertainment, reason: .rule(ruleID: rule.id)),
      "control: enabled, the same rule is suggested")
  }

  /// Every blank description normalises to "", so blank rows share nothing but
  /// the absence of a merchant.
  func testBlankDescriptionsAreNotAMerchantHistory() throws {
    let (suggester, context) = try makeSuggester()
    insertRow("", category: food, source: .manual, into: context)
    insertRow("", category: food, source: .manual, into: context)
    let row = insertRow("", category: nil, source: .none, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))
  }

  // MARK: - History

  /// (2) Two Food against one Shopping. A different merchant filed Shopping
  /// three times must not count: the grouping is on the description.
  func testTheMerchantsMajorityCategoryIsSuggestedWithItsCount() throws {
    let (suggester, context) = try makeSuggester()
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    insertRow("SWIGGY", category: shopping, source: .manual, into: context)
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    for _ in 0..<3 {
      insertRow("ZOMATO", category: shopping, source: .manual, into: context)
    }
    let row = insertRow("SWIGGY", category: nil, source: .none, into: context)

    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: food, reason: .merchantHistory(matches: 2)))
  }

  /// Ties by count then id. Shopping is filed first, so a result that followed
  /// insertion or fetch order would pick it.
  func testATieGoesToTheSmallerCategoryIDWhicheverWasFiledFirst() throws {
    let (suggester, context) = try makeSuggester()
    insertRow("SWIGGY", category: shopping, source: .manual, into: context)
    insertRow("SWIGGY", category: food, source: .manual, into: context)
    let row = insertRow("SWIGGY", category: nil, source: .none, into: context)

    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: food, reason: .merchantHistory(matches: 1)))
  }

  // MARK: - Rules

  /// (3) No siblings. A second, lower-precedence rule also matches and is
  /// inserted first, so the answer has to come from precedence, not fetch order.
  func testWithNoHistoryTheFirstEnabledRuleInPrecedenceOrderIsSuggested() throws {
    let (suggester, context) = try makeSuggester()
    insertRule("*NET*", category: bills, priority: 5, into: context)
    let rule = insertRule("*NETFLIX*", category: entertainment, priority: 0, into: context)
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: entertainment, reason: .rule(ruleID: rule.id)))
  }

  /// (4) The user filed this merchant as Bills once; a rule says Entertainment.
  func testHistoryOutranksAMatchingRule() throws {
    let (suggester, context) = try makeSuggester()
    insertRule("*NETFLIX*", category: entertainment, into: context)
    insertRow("NETFLIX COM", category: bills, source: .manual, into: context)
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: bills, reason: .merchantHistory(matches: 1)))
  }

  // MARK: -

  /// Letters only in every description: `normalizeDescription` strips digit
  /// runs, and a fixture that relied on digits to tell merchants apart would
  /// match nothing. The normalised form is written directly here.
  @discardableResult
  private func insertRow(
    _ normalized: String,
    category: UUID?,
    source: CategorySource,
    into context: ModelContext
  ) -> Transaction {
    let row = Transaction(
      descriptionText: normalized,
      normalizedDescription: normalized,
      amountMinor: 499_00,
      categoryID: category,
      categorySourceRaw: source.rawValue)
    context.insert(row)
    try? context.save()
    return row
  }

  @discardableResult
  private func insertRule(
    _ pattern: String,
    category: UUID,
    priority: Int = 0,
    enabled: Bool = true,
    into context: ModelContext
  ) -> Rule {
    let rule = Rule(pattern: pattern, categoryID: category, priority: priority, isEnabled: enabled)
    context.insert(rule)
    try? context.save()
    return rule
  }

  private func makeSuggester() throws -> (SwiftDataCategorySuggester, ModelContext) {
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
    return (SwiftDataCategorySuggester(context: context), context)
  }

  // MARK: - Rule scope (W2-5)

  /// A rule the row is outside the scope of is not offered for that row.
  ///
  /// The suggester reads rules through `TransactionSnapshotBridge` and matches
  /// the whole row, so the same condition that stops the rule firing on ingest
  /// stops it being suggested. The control is the point: the identical rule,
  /// scoped the other way, *is* suggested — without it this would also pass if
  /// the suggester had simply stopped working.
  func testARuleScopedAwayFromTheRowIsNotSuggestedForIt() throws {
    let (suggester, context) = try makeSuggester()
    let rule = insertRule("*NETFLIX*", category: entertainment, into: context)
    rule.scope = RuleScope(direction: .credit)
    try context.save()
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertNil(
      try suggester.suggestion(for: row.id),
      "the row is a debit; the rule only fires on credits")

    rule.scope = RuleScope(direction: .debit)
    try context.save()
    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: entertainment, reason: .rule(ruleID: rule.id)),
      "control: scoped to the direction this row actually has")
  }

  /// The amount band, which is the scope field a description can say nothing
  /// about at all. `insertRow` writes 499_00.
  func testARuleScopedToAnAmountBandTheRowIsOutsideIsNotSuggested() throws {
    let (suggester, context) = try makeSuggester()
    let rule = insertRule("*NETFLIX*", category: entertainment, into: context)
    rule.scope = RuleScope(minAmountMinor: 1_000_00)
    try context.save()
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertNil(try suggester.suggestion(for: row.id))

    rule.scope = RuleScope(minAmountMinor: 100_00)
    try context.save()
    XCTAssertNotNil(try suggester.suggestion(for: row.id), "control: the band now contains it")
  }

  /// An unscoped rule suggests exactly what it suggested before §W2-5.
  func testAnUnscopedRuleIsStillSuggestedTheSameWay() throws {
    let (suggester, context) = try makeSuggester()
    let rule = insertRule("*NETFLIX*", category: entertainment, into: context)
    let row = insertRow("NETFLIX COM", category: nil, source: .none, into: context)

    XCTAssertEqual(rule.scope, .any)
    XCTAssertEqual(
      try suggester.suggestion(for: row.id),
      CategorySuggestion(categoryID: entertainment, reason: .rule(ruleID: rule.id)))
  }
}
