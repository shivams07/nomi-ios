import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `PlanModel` with spy stores (S7). Dismissal goes through the recurring store
/// once, and the row leaves the list only after the reload that follows it.
@MainActor
final class PlanModelTests: XCTestCase {
  struct Refused: Error {}

  @MainActor
  private final class SpyRecurringStore: RecurringInsightsStore {
    var all: [RecurringSeries]
    private(set) var dismissed: Set<String> = []
    private(set) var dismissCalls = 0
    var failsDismiss = false
    var failsRead = false

    init(all: [RecurringSeries]) {
      self.all = all
    }

    func recurringSeries() throws -> [RecurringSeries] {
      if failsRead { throw Refused() }
      return all.filter { !dismissed.contains($0.id) }
    }

    func dismiss(seriesID: String) throws {
      dismissCalls += 1
      if failsDismiss { throw Refused() }
      dismissed.insert(seriesID)
    }

    func dismissedSeriesIDs() -> Set<String> { dismissed }
  }

  @MainActor
  private final class SpyInsightsStore: InsightsStore {
    var progress: [BudgetProgress] = []
    var byCategory: [CategorySlice] = []
    var failsProgress = false

    func insights(for period: InsightPeriod) throws -> PeriodInsights {
      PeriodInsights(
        period: period, debitMinor: 0, creditMinor: 0, netMinor: 0,
        priorDebitMinor: nil, priorCreditMinor: nil, transactionCount: 0,
        byDay: [], byCategory: byCategory, topMerchants: [],
        needsReviewCount: 0, uncategorizedCount: 0
      )
    }

    func trend(months: Int) throws -> [MonthBucket] { [] }
    func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }

    func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
      if failsProgress { throw Refused() }
      return progress
    }

    func transactions(in period: InsightPeriod) throws -> [Transaction] { [] }
  }

  private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
  }()

  private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!

  private func series(_ id: String, amount: Int) -> RecurringSeries {
    RecurringSeries(
      id: id,
      label: id.capitalized,
      amountMinor: amount,
      occurrences: 3,
      lastDate: now,
      nextExpected: now
    )
  }

  private func progress(_ name: String, budget: Int, spent: Int) -> BudgetProgress {
    BudgetProgress(
      id: UUID(),
      categoryName: name,
      symbolName: "bag",
      paletteSlot: 1,
      budgetMinor: budget,
      spentMinor: spent,
      fraction: budget > 0 ? Double(spent) / Double(budget) : 0,
      periodKey: "2026-11"
    )
  }

  private func makeModel(
    insights: SpyInsightsStore? = nil,
    recurring: SpyRecurringStore?
  ) -> PlanModel {
    PlanModel(
      insightsStore: insights ?? SpyInsightsStore(),
      recurringStore: recurring,
      calendar: calendar,
      now: { self.now }
    )
  }

  /// Dismissal calls the store once, and the row is gone after the reload.
  func testDismissCallsTheStoreOnceAndTheRowLeaves() {
    let store = SpyRecurringStore(all: [series("netflix", amount: 649_00), series("act", amount: 850_00)])
    let model = makeModel(recurring: store)
    model.load()
    XCTAssertEqual(model.series.map(\.id), ["netflix", "act"])

    model.dismiss(seriesID: "netflix")

    XCTAssertEqual(store.dismissCalls, 1)
    XCTAssertEqual(model.series.map(\.id), ["act"])
    XCTAssertFalse(model.dismissFailed)
  }

  /// A refused dismissal keeps the row and says so, rather than hiding it.
  func testDismissFailureKeepsTheRowAndSetsTheFlag() {
    let store = SpyRecurringStore(all: [series("netflix", amount: 649_00)])
    store.failsDismiss = true
    let model = makeModel(recurring: store)
    model.load()

    model.dismiss(seriesID: "netflix")

    XCTAssertEqual(model.series.map(\.id), ["netflix"])
    XCTAssertTrue(model.dismissFailed)
  }

  /// The recurring total is the sum of the series still shown. A dismissed
  /// series is not counted.
  func testMonthlyTotalIsTheSumOfTheSeriesShown() {
    let store = SpyRecurringStore(all: [series("netflix", amount: 649_00), series("rent", amount: 18_000_00), series("act", amount: 850_00)])
    let model = makeModel(recurring: store)
    model.load()
    XCTAssertEqual(model.monthlyRecurringMinor, 19_499_00)

    model.dismiss(seriesID: "rent")

    XCTAssertEqual(model.monthlyRecurringMinor, 1_499_00)
  }

  func testRecurringReadFailureIsAFailedState() {
    let store = SpyRecurringStore(all: [])
    store.failsRead = true
    let model = makeModel(recurring: store)
    model.load()
    XCTAssertEqual(model.recurringState, .failed)
    XCTAssertTrue(model.series.isEmpty)
  }

  /// No recurring store is wired in some launches; the section is then unavailable.
  func testNoRecurringStoreIsUnavailable() {
    let model = makeModel(recurring: nil)
    model.load()
    XCTAssertEqual(model.recurringState, .unavailable)
    XCTAssertEqual(model.monthlyRecurringMinor, 0)
  }

  /// Totals are the sum of every budget, and the remainder is what is left.
  /// ₹5,000 budget with ₹2,000 spent and ₹2,000 with ₹2,600 spent: ₹7,000 with
  /// ₹4,600 spent leaves ₹2,400.
  func testTotalsSumEveryBudgetAndLeaveTheRemainder() {
    let insights = SpyInsightsStore()
    insights.progress = [progress("Groceries", budget: 5_000_00, spent: 2_000_00), progress("Transport", budget: 2_000_00, spent: 2_600_00)]
    let model = makeModel(insights: insights, recurring: nil)
    model.load()
    XCTAssertEqual(model.totals?.budgetMinor, 7_000_00)
    XCTAssertEqual(model.totals?.spentMinor, 4_600_00)
    XCTAssertEqual(model.totals?.remainingMinor, 2_400_00)
  }

  func testNoBudgetsHasNoTotals() {
    let model = makeModel(recurring: nil)
    model.load()
    XCTAssertEqual(model.progress?.isEmpty, true)
    XCTAssertNil(model.totals)
  }

  func testBudgetReadFailureIsNilProgress() {
    let insights = SpyInsightsStore()
    insights.failsProgress = true
    let model = makeModel(insights: insights, recurring: nil)
    model.load()
    XCTAssertNil(model.progress)
    XCTAssertNil(model.totals)
  }

  /// The suggestion reads three months of categories and skips a budgeted one.
  func testSuggestionReadsThreeMonthsAndSkipsBudgeted() {
    let insights = SpyInsightsStore()
    let budgeted = UUID()
    insights.progress = [BudgetProgress(id: budgeted, categoryName: "Food", symbolName: "fork.knife", paletteSlot: 0, budgetMinor: 5_000_00, spentMinor: 0, fraction: 0, periodKey: "2026-11")]
    insights.byCategory = [
      CategorySlice(id: budgeted, name: "Food", symbolName: "fork.knife", paletteSlot: 0, totalMinor: 9_000_00, share: 0),
      CategorySlice(id: UUID(), name: "Bills", symbolName: "bolt", paletteSlot: 3, totalMinor: 6_900_00, share: 0),
    ]
    let model = makeModel(insights: insights, recurring: nil)
    model.load()
    XCTAssertEqual(model.suggestion?.slice.name, "Bills")
    XCTAssertEqual(model.suggestion?.averageMinor, 2_300_00)
  }
}
