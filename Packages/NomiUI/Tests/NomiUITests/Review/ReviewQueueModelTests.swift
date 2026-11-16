import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// S4 steps 2 and 3's writes. The model reads the queue and owns the order, the
/// choices, the selection and every write. The spies record calls and mutate the
/// rows the way the stores do, so a test can see what was written and in what order.
@MainActor
final class ReviewQueueModelTests: XCTestCase {
  private struct SpyFailure: Error {}

  @MainActor private final class SpyTransactionStore: TransactionStore {
    var flagged: [NomiCore.Transaction] = []
    var rows: [UUID: NomiCore.Transaction] = [:]
    var failQueue = false
    var failSetCategory = false
    var failDelete = false
    private(set) var setCategoryCalls: [(id: UUID, categoryID: UUID?)] = []
    private(set) var setAccountCalls: [(id: UUID, accountID: UUID?)] = []
    private(set) var deletedIDs: [UUID] = []
    private(set) var dismissedIDs: [UUID] = []

    func add(_ draft: ManualTransactionDraft) throws -> NomiCore.Transaction { throw SpyFailure() }

    func setCategory(_ id: UUID, to categoryID: UUID?) throws {
      if failSetCategory { throw SpyFailure() }
      setCategoryCalls.append((id, categoryID))
      guard let row = rows[id] else { return }
      row.categoryID = categoryID
      row.categorySource = .manual
      row.appliedRuleID = nil
    }

    func setAccount(_ id: UUID, to accountID: UUID?) throws {
      setAccountCalls.append((id, accountID))
      rows[id]?.accountID = accountID
    }

    func delete(_ id: UUID) throws {
      if failDelete { throw SpyFailure() }
      deletedIDs.append(id)
    }

    func reviewQueue() throws -> [NomiCore.Transaction] {
      if failQueue { throw SpyFailure() }
      return flagged
    }

    func dismissReview(_ id: UUID) throws {
      dismissedIDs.append(id)
      rows[id]?.needsReview = false
    }

    func lastUsedCategoryID() -> UUID? { nil }
  }

  @MainActor private final class SpyInsightsStore: InsightsStore {
    var monthRows: [NomiCore.Transaction] = []
    var categories: [CategorySlice] = []
    var failMonth = false

    func insights(for period: InsightPeriod) throws -> PeriodInsights {
      PeriodInsights(
        period: period, debitMinor: 0, creditMinor: 0, netMinor: 0,
        priorDebitMinor: nil, priorCreditMinor: nil, transactionCount: 0,
        byDay: [], byCategory: categories, topMerchants: [],
        needsReviewCount: 0, uncategorizedCount: 0)
    }
    func trend(months: Int) throws -> [MonthBucket] { [] }
    func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }
    func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
    func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] {
      if failMonth { throw SpyFailure() }
      return monthRows
    }
  }

  @MainActor private final class SpyRuleStore: RuleStore {
    var failCreate = false
    private(set) var creates: [(pattern: String, categoryID: UUID)] = []

    @discardableResult
    func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
      if failCreate { throw SpyFailure() }
      creates.append((pattern, categoryID))
      return RuleApplyResult(matched: 0, recategorized: 0)
    }
    @discardableResult
    func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult {
      throw SpyFailure()
    }
    func setScope(_ id: UUID, _ scope: RuleScope) throws { throw SpyFailure() }
    func setEnabled(_ id: UUID, _ enabled: Bool) throws { throw SpyFailure() }
    func delete(_ id: UUID) throws { throw SpyFailure() }
    func reorder(_ orderedIDs: [UUID]) throws { throw SpyFailure() }
    func preview(pattern: String, scope: RuleScope) throws -> Int { 0 }
  }

  @MainActor private final class SpySuggester: CategorySuggesting {
    var suggestions: [UUID: CategorySuggestion] = [:]
    func suggestion(for transactionID: UUID) throws -> CategorySuggestion? { suggestions[transactionID] }
  }

  /// The four stores behind one model, with the rows indexed so writes reach them.
  @MainActor private final class Fixture {
    let transactions = SpyTransactionStore()
    let insights = SpyInsightsStore()
    let rules = SpyRuleStore()
    let suggester = SpySuggester()
    let now: Date
    private let calendar = NomiCalendar.india

    init(flagged: [NomiCore.Transaction] = [], monthRows: [NomiCore.Transaction] = [], now: Date) {
      self.now = now
      transactions.flagged = flagged
      insights.monthRows = monthRows
      for row in flagged + monthRows {
        transactions.rows[row.id] = row
      }
    }

    func makeModel() -> ReviewQueueModel {
      let now = self.now
      return ReviewQueueModel(
        transactionStore: transactions,
        insightsStore: insights,
        ruleStore: rules,
        suggester: suggester,
        now: { now },
        calendar: calendar)
    }
  }

  private let calendar = NomiCalendar.india

  private func day(_ dayOfMonth: Int, month: Int = 11, hour: Int = 12, minute: Int = 0) -> Date {
    let parts = DateComponents(
      calendar: calendar, timeZone: calendar.timeZone,
      year: 2026, month: month, day: dayOfMonth, hour: hour, minute: minute)
    return calendar.date(from: parts)!
  }

  private var now: Date { day(16) }

  /// An email-sourced row with a merchant name that normalises to "OLACABS".
  private func flaggedRow(
    _ name: String = "Olacabs",
    on date: Date? = nil,
    categoryID: UUID? = nil,
    categorySource: CategorySource = .none,
    appliedRuleID: UUID? = nil,
    reason: NeedsReviewReason = .heuristic,
    accountID: UUID? = UUID()
  ) -> NomiCore.Transaction {
    NomiCore.Transaction(
      date: date ?? day(15),
      descriptionText: name,
      merchantName: name,
      normalizedDescription: normalizeDescription(name),
      amountMinor: 84_500,
      categoryID: categoryID,
      categorySourceRaw: categorySource.rawValue,
      appliedRuleID: appliedRuleID,
      accountID: accountID,
      sourceRaw: IngestSource.email.rawValue,
      needsReview: true,
      needsReviewReasonRaw: reason.rawValue
    )
  }

  private func monthRow(_ name: String, on date: Date? = nil) -> NomiCore.Transaction {
    NomiCore.Transaction(
      date: date ?? day(12),
      descriptionText: name,
      merchantName: name,
      normalizedDescription: normalizeDescription(name),
      amountMinor: 30_000,
      accountID: UUID(),
      sourceRaw: IngestSource.file.rawValue
    )
  }

  private func slice(_ id: UUID, _ totalMinor: Int) -> CategorySlice {
    CategorySlice(id: id, name: "Category", paletteSlot: 0, totalMinor: totalMinor, share: 0)
  }

  // MARK: - Load, order and progress

  func testLoadListsTheQueueAndCountsProgressFromOne() {
    let first = flaggedRow("Olacabs", on: day(15))
    let second = flaggedRow("Swiggy", on: day(14))
    let model = Fixture(flagged: [first, second], now: now).makeModel()

    model.load()

    XCTAssertEqual(model.current?.id, first.id)
    XCTAssertEqual(model.progress, "1 of 2")
    XCTAssertEqual(model.progressFraction, 0.5, accuracy: 0.0001)
    XCTAssertFalse(model.isFinished)
  }

  func testAnEmptyQueueIsFinished() {
    let model = Fixture(now: now).makeModel()

    model.load()

    XCTAssertTrue(model.isLoaded)
    XCTAssertNil(model.current)
    XCTAssertTrue(model.isFinished)
  }

  func testAFailedQueueReadIsNotFinished() {
    let fixture = Fixture(flagged: [flaggedRow()], now: now)
    fixture.transactions.failQueue = true
    let model = fixture.makeModel()

    model.load()

    XCTAssertTrue(model.loadFailed)
    XCTAssertFalse(model.isFinished)
    XCTAssertNil(model.current)
  }

  // MARK: - Choices and selection

  func testChoicesNeverRepeatTheBestGuess() {
    let best = UUID()
    let other = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 2))
    fixture.insights.categories = [slice(best, 500), slice(other, 100)]
    let model = fixture.makeModel()

    model.load()

    XCTAssertEqual(model.bestGuessID, best)
    XCTAssertEqual(model.choices, [.category(best), .category(other), .allCategories])
    XCTAssertEqual(model.selectedCategoryID, best)
  }

  func testConfirmIsOffUntilACategoryIsChosen() {
    let row = flaggedRow()
    let model = Fixture(flagged: [row], now: now).makeModel()
    model.load()

    XCTAssertNil(model.selectedCategoryID)
    XCTAssertFalse(model.canConfirm)

    let picked = UUID()
    model.selectedCategoryID = picked
    XCTAssertTrue(model.canConfirm)
  }

  func testRememberIsOffWhenThereIsNoMerchantPattern() {
    let blank = NomiCore.Transaction(
      date: day(15), descriptionText: "", merchantName: nil, normalizedDescription: "",
      needsReview: true, needsReviewReasonRaw: NeedsReviewReason.heuristic.rawValue)
    let model = Fixture(flagged: [blank], now: now).makeModel()

    model.load()

    XCTAssertNil(model.rememberPattern)
    XCTAssertFalse(model.remember)
  }

  // MARK: - Confirm, skip, delete

  func testConfirmWithTheBestGuessAndRememberWritesOneCategoryOneRuleOneDismissAndAdvances() {
    let best = UUID()
    let first = flaggedRow("Olacabs", on: day(15))
    let second = flaggedRow("Swiggy", on: day(14))
    let fixture = Fixture(flagged: [first, second], now: now)
    fixture.suggester.suggestions[first.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 3))
    let model = fixture.makeModel()
    model.load()

    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.count, 1)
    XCTAssertEqual(fixture.transactions.setCategoryCalls.first?.id, first.id)
    XCTAssertEqual(fixture.transactions.setCategoryCalls.first?.categoryID, best)
    XCTAssertEqual(fixture.rules.creates.count, 1)
    XCTAssertEqual(fixture.rules.creates.first?.pattern, "*OLACABS*")
    XCTAssertEqual(fixture.rules.creates.first?.categoryID, best)
    XCTAssertEqual(fixture.transactions.dismissedIDs, [first.id])
    XCTAssertEqual(model.current?.id, second.id)
    XCTAssertEqual(model.progress, "2 of 2")
  }

  func testRememberOffWritesNoRule() {
    let best = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 1))
    let model = fixture.makeModel()
    model.load()
    model.remember = false

    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.count, 1)
    XCTAssertTrue(fixture.rules.creates.isEmpty)
    XCTAssertEqual(fixture.transactions.dismissedIDs, [row.id])
  }

  func testSkipWritesNothingAndAdvances() {
    let first = flaggedRow("Olacabs", on: day(15))
    let second = flaggedRow("Swiggy", on: day(14))
    let fixture = Fixture(flagged: [first, second], now: now)
    let model = fixture.makeModel()
    model.load()

    model.skip()

    XCTAssertEqual(model.current?.id, second.id)
    XCTAssertTrue(fixture.transactions.setCategoryCalls.isEmpty)
    XCTAssertTrue(fixture.transactions.deletedIDs.isEmpty)
    XCTAssertTrue(fixture.transactions.dismissedIDs.isEmpty)
    XCTAssertTrue(fixture.rules.creates.isEmpty)
  }

  func testNotATransactionDeletesOnlyWhenTheUserConfirms() {
    let first = flaggedRow("Olacabs", on: day(15))
    let second = flaggedRow("Swiggy", on: day(14))
    let fixture = Fixture(flagged: [first, second], now: now)
    let model = fixture.makeModel()
    model.load()

    XCTAssertTrue(fixture.transactions.deletedIDs.isEmpty)

    model.notATransaction()

    XCTAssertEqual(fixture.transactions.deletedIDs, [first.id])
    XCTAssertTrue(fixture.transactions.setCategoryCalls.isEmpty)
    XCTAssertEqual(model.current?.id, second.id)
  }

  func testAFailedDeleteKeepsTheRowOnScreen() {
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.transactions.failDelete = true
    let model = fixture.makeModel()
    model.load()

    model.notATransaction()

    XCTAssertEqual(model.current?.id, row.id)
    XCTAssertNotNil(model.errorMessage)
  }

  func testAnUnflaggedMonthRowIsCategorisedWithoutADismiss() {
    let best = UUID()
    let row = monthRow("Uncategorised month row")
    let fixture = Fixture(monthRows: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 2))
    let model = fixture.makeModel()
    model.load()

    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.map(\.categoryID), [best])
    XCTAssertTrue(fixture.transactions.dismissedIDs.isEmpty)
    XCTAssertTrue(model.isFinished)
  }

  func testSetCategoryIsSkippedWhenTheCategoryIsUnchanged() {
    let current = UUID()
    let row = flaggedRow(categoryID: current, categorySource: .manual)
    let fixture = Fixture(flagged: [row], now: now)
    let model = fixture.makeModel()
    model.load()

    XCTAssertEqual(model.selectedCategoryID, current)
    model.confirmNext()

    XCTAssertTrue(fixture.transactions.setCategoryCalls.isEmpty)
    XCTAssertEqual(fixture.transactions.dismissedIDs, [row.id])
  }

  // MARK: - Remember and the rule that already exists

  func testRememberWritesNoRuleWhenTheRowIsAlreadyFiledByARuleUnderThatCategory() {
    let category = UUID()
    let row = flaggedRow(categoryID: category, categorySource: .rule, appliedRuleID: UUID())
    let fixture = Fixture(flagged: [row], now: now)
    let model = fixture.makeModel()
    model.load()
    XCTAssertEqual(model.selectedCategoryID, category)

    model.confirmNext()

    XCTAssertTrue(fixture.transactions.setCategoryCalls.isEmpty)
    XCTAssertTrue(fixture.rules.creates.isEmpty)
    XCTAssertEqual(fixture.transactions.dismissedIDs, [row.id])
  }

  func testRememberWritesNoRuleWhenASuggestedRuleAlreadyFilesTheMerchantUnderThatCategory() {
    let category = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: category, reason: .rule(ruleID: UUID()))
    let model = fixture.makeModel()
    model.load()

    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.map(\.categoryID), [category])
    XCTAssertTrue(fixture.rules.creates.isEmpty)
    XCTAssertEqual(fixture.transactions.dismissedIDs, [row.id])
  }

  func testRememberCreatesARuleWhenTheChosenCategoryDiffersFromTheExistingRule() {
    let ruled = UUID()
    let chosen = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: ruled, reason: .rule(ruleID: UUID()))
    let model = fixture.makeModel()
    model.load()
    model.selectedCategoryID = chosen

    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.map(\.categoryID), [chosen])
    XCTAssertEqual(fixture.rules.creates.map(\.categoryID), [chosen])
    XCTAssertEqual(fixture.rules.creates.map(\.pattern), ["*OLACABS*"])
  }

  // MARK: - Failures

  func testARuleCreateFailureShowsAnErrorAndDoesNotAdvance() {
    let best = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 1))
    fixture.rules.failCreate = true
    let model = fixture.makeModel()
    model.load()

    model.confirmNext()

    XCTAssertEqual(model.errorMessage, "That didn't save. Try again.")
    XCTAssertEqual(model.current?.id, row.id)
    XCTAssertTrue(fixture.transactions.dismissedIDs.isEmpty)
  }

  func testARetryAfterARuleFailureDoesNotCategoriseTwice() {
    let best = UUID()
    let row = flaggedRow()
    let fixture = Fixture(flagged: [row], now: now)
    fixture.suggester.suggestions[row.id] = CategorySuggestion(categoryID: best, reason: .merchantHistory(matches: 1))
    fixture.rules.failCreate = true
    let model = fixture.makeModel()
    model.load()
    model.confirmNext()

    fixture.rules.failCreate = false
    model.confirmNext()

    XCTAssertEqual(fixture.transactions.setCategoryCalls.count, 1)
    XCTAssertEqual(fixture.rules.creates.map(\.categoryID), [best])
    XCTAssertEqual(fixture.transactions.dismissedIDs, [row.id])
    XCTAssertTrue(model.isFinished)
  }

  // MARK: - Account

  func testAssigningAnAccountWritesItAndStaysOnTheRow() {
    let account = UUID()
    let row = flaggedRow(categoryID: nil, reason: .unidentifiedAccount, accountID: nil)
    let fixture = Fixture(flagged: [row], now: now)
    let model = fixture.makeModel()
    model.load()

    XCTAssertTrue(model.showsAccountRow)

    model.assignAccount(account)

    XCTAssertEqual(fixture.transactions.setAccountCalls.count, 1)
    XCTAssertEqual(fixture.transactions.setAccountCalls.first?.id, row.id)
    XCTAssertEqual(fixture.transactions.setAccountCalls.first?.accountID, account)
    XCTAssertEqual(model.accountID, account)
    XCTAssertEqual(model.current?.id, row.id)
  }
}
