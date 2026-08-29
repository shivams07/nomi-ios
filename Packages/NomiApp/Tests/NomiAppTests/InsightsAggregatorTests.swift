import NomiCore
import XCTest

@testable import NomiApp

/// Every number on the dashboard, reports page and budget list is produced here.
///
/// The calendar is pinned to Asia/Kolkata rather than `.current` on purpose. CI
/// runs on a UTC machine and a phone in India does not; a day-bucket test that
/// passes on one and fails on the other would be a real bug found by accident,
/// or — far more likely — a correct implementation "fixed" until it broke.
final class InsightsAggregatorTests: XCTestCase {

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.timeZone = calendar.timeZone
    return calendar.date(from: components)!
  }

  private func row(
    _ amountMinor: Int,
    _ direction: Direction = .debit,
    on date: Date,
    category: UUID? = nil,
    account: UUID? = nil,
    normalized: String = "MERCHANT",
    merchant: String? = nil,
    description: String = "raw description",
    needsReview: Bool = false
  ) -> LedgerRow {
    LedgerRow(
      id: UUID(),
      date: date,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      categoryID: category,
      accountID: account,
      normalizedDescription: normalized,
      merchantName: merchant,
      descriptionText: description,
      needsReview: needsReview
    )
  }

  // MARK: - Period key

  func testPeriodKeyIsZeroPaddedYearAndMonth() {
    XCTAssertEqual(InsightsAggregator.periodKey(year: 2026, month: 4), "2026-04")
    XCTAssertEqual(InsightsAggregator.periodKey(year: 2026, month: 12), "2026-12")
  }

  // MARK: - Prior range

  func testPriorRangeOfAMonthIsTheMonthBefore() {
    let prior = InsightsAggregator.priorRange(for: .month(year: 2026, month: 5), calendar: calendar)
    XCTAssertEqual(prior, dateRange(for: .month(year: 2026, month: 4), calendar: calendar))
  }

  /// The wrap. January's prior month is December of the *previous* year, and
  /// getting this wrong shows up as a hero-card delta that is silently wrong
  /// once a year.
  func testPriorRangeOfJanuaryIsTheDecemberBefore() {
    let prior = InsightsAggregator.priorRange(for: .month(year: 2026, month: 1), calendar: calendar)
    XCTAssertEqual(prior, dateRange(for: .month(year: 2025, month: 12), calendar: calendar))
  }

  func testPriorRangeOfAFinancialYearIsThePreviousFinancialYear() {
    let prior = InsightsAggregator.priorRange(for: .financialYear(startingYear: 2026), calendar: calendar)
    XCTAssertEqual(prior, dateRange(for: .financialYear(startingYear: 2025), calendar: calendar))
  }

  /// A trailing window has no prior *period* to name, so its comparison is the
  /// same length immediately before it — and it must abut, with no gap and no
  /// overlap, or the two halves of the delta count some days twice.
  func testPriorRangeOfATrailingWindowAbutsIt() {
    let now = date(2026, 8, 29)
    let current = dateRange(for: .trailingMonths(3), calendar: calendar, now: now)
    let prior = InsightsAggregator.priorRange(for: .trailingMonths(3), calendar: calendar, now: now)

    XCTAssertEqual(prior?.upperBound, current.lowerBound)
    XCTAssertEqual(
      prior?.lowerBound,
      calendar.date(byAdding: .month, value: -3, to: current.lowerBound)
    )
  }

  func testAllTimeHasNoPriorPeriod() {
    XCTAssertNil(InsightsAggregator.priorRange(for: .allTime, calendar: calendar))
  }

  // MARK: - Insights

  func testTotalsSplitByDirectionAndNetIsCreditMinusDebit() {
    let rows = [
      row(1_000, .debit, on: date(2026, 4, 2)),
      row(2_500, .debit, on: date(2026, 4, 3)),
      row(50_000, .credit, on: date(2026, 4, 1)),
    ]

    let insights = InsightsAggregator.insights(
      period: .month(year: 2026, month: 4),
      rows: rows,
      categories: [:],
      priorRows: nil,
      calendar: calendar
    )

    XCTAssertEqual(insights.debitMinor, 3_500)
    XCTAssertEqual(insights.creditMinor, 50_000)
    XCTAssertEqual(insights.netMinor, 46_500)
    XCTAssertEqual(insights.transactionCount, 3)
  }

  /// `FakeInsightsStore` returns `nil` for both, so `HeroTotalCard`'s delta has
  /// never had a value to render. The real store supplies them.
  func testPriorTotalsArePopulatedWhenAPriorWindowIsGiven() {
    let insights = InsightsAggregator.insights(
      period: .month(year: 2026, month: 4),
      rows: [row(1_000, .debit, on: date(2026, 4, 2))],
      categories: [:],
      priorRows: [
        row(800, .debit, on: date(2026, 3, 2)),
        row(20_000, .credit, on: date(2026, 3, 5)),
      ],
      calendar: calendar
    )

    XCTAssertEqual(insights.priorDebitMinor, 800)
    XCTAssertEqual(insights.priorCreditMinor, 20_000)
  }

  func testPriorTotalsAreNilForAllTime() {
    let insights = InsightsAggregator.insights(
      period: .allTime,
      rows: [row(1_000, .debit, on: date(2026, 4, 2))],
      categories: [:],
      priorRows: nil,
      calendar: calendar
    )

    XCTAssertNil(insights.priorDebitMinor)
    XCTAssertNil(insights.priorCreditMinor)
  }

  func testNeedsReviewAndUncategorizedCountsCoverBothDirections() {
    let categorized = UUID()
    let rows = [
      row(100, .debit, on: date(2026, 4, 1), category: categorized),
      row(200, .debit, on: date(2026, 4, 1), needsReview: true),
      row(300, .credit, on: date(2026, 4, 1), needsReview: true),
    ]

    let insights = InsightsAggregator.insights(
      period: .month(year: 2026, month: 4),
      rows: rows,
      categories: [:],
      priorRows: nil,
      calendar: calendar
    )

    XCTAssertEqual(insights.needsReviewCount, 2)
    XCTAssertEqual(insights.uncategorizedCount, 2)
  }

  // MARK: - By day

  func testDayBucketsAreDebitOnlyAndAscending() {
    let rows = [
      row(500, .debit, on: date(2026, 4, 3)),
      row(100, .debit, on: date(2026, 4, 1)),
      row(200, .debit, on: date(2026, 4, 1, hour: 23)),
      row(99_000, .credit, on: date(2026, 4, 2)),
    ]

    let buckets = InsightsAggregator.byDay(rows.filter(\.isDebit), calendar: calendar)

    XCTAssertEqual(buckets.map(\.debitMinor), [300, 500])
    XCTAssertEqual(buckets.map(\.id), [
      calendar.startOfDay(for: date(2026, 4, 1)),
      calendar.startOfDay(for: date(2026, 4, 3)),
    ])
  }

  /// A day with a credit and no debit produces no bucket, rather than a zero
  /// one. The chart draws what it is given.
  func testADayWithNoSpendHasNoBucket() {
    let buckets = InsightsAggregator.byDay([], calendar: calendar)
    XCTAssertTrue(buckets.isEmpty)
  }

  // MARK: - By category

  func testCategorySlicesShareOfTotalAndSortOrder() {
    let food = UUID()
    let rent = UUID()
    let categories: [UUID: CategoryRef] = [
      food: CategoryRef(id: food, name: "UPI & Food Delivery", paletteSlot: 0),
      rent: CategoryRef(id: rent, name: "Rent", paletteSlot: 3),
    ]
    let debits = [
      row(2_000, .debit, on: date(2026, 4, 1), category: food),
      row(8_000, .debit, on: date(2026, 4, 2), category: rent),
    ]

    let slices = InsightsAggregator.byCategory(debits, categories: categories, debitTotal: 10_000)

    XCTAssertEqual(slices.map(\.name), ["Rent", "UPI & Food Delivery"])
    XCTAssertEqual(slices.map(\.paletteSlot), [3, 0])
    XCTAssertEqual(slices.map(\.share).reduce(0, +), 1, accuracy: 0.0001)
  }

  /// A nil `categoryID` folds into the display sentinel — not into a real
  /// seeded row — and shows as "Uncategorized" at slot 6.
  func testUncategorizedSpendFoldsIntoTheSentinelSlice() {
    let slices = InsightsAggregator.byCategory(
      [row(1_000, .debit, on: date(2026, 4, 1))],
      categories: [:],
      debitTotal: 1_000
    )

    XCTAssertEqual(slices.count, 1)
    XCTAssertEqual(slices.first?.id, NomiCore.Category.uncategorizedID)
    XCTAssertEqual(slices.first?.name, "Uncategorized")
    XCTAssertEqual(slices.first?.paletteSlot, 6)
  }

  func testZeroSpendProducesZeroSharesRatherThanNaN() {
    let slices = InsightsAggregator.byCategory(
      [row(0, .debit, on: date(2026, 4, 1))],
      categories: [:],
      debitTotal: 0
    )
    XCTAssertEqual(slices.first?.share, 0)
  }

  /// The fake sorts by amount alone and builds its groups in a `Dictionary`,
  /// whose iteration order is seeded per process — so two categories with equal
  /// spend come out in a different order on each launch. The tie-break is what
  /// stops a list from reshuffling itself between renders.
  func testEqualSpendIsBrokenByNameSoTheOrderIsStable() {
    let alpha = UUID()
    let zulu = UUID()
    let categories: [UUID: CategoryRef] = [
      alpha: CategoryRef(id: alpha, name: "Alpha", paletteSlot: 0),
      zulu: CategoryRef(id: zulu, name: "Zulu", paletteSlot: 1),
    ]
    let debits = [
      row(5_000, .debit, on: date(2026, 4, 1), category: zulu),
      row(5_000, .debit, on: date(2026, 4, 1), category: alpha),
    ]

    for _ in 0..<10 {
      let slices = InsightsAggregator.byCategory(debits, categories: categories, debitTotal: 10_000)
      XCTAssertEqual(slices.map(\.name), ["Alpha", "Zulu"])
    }
  }

  // MARK: - Top merchants

  func testMerchantsRollUpOnNormalizedDescription() {
    let debits = [
      row(400, .debit, on: date(2026, 4, 1), normalized: "SWIGGY ORDER", merchant: "Swiggy"),
      row(600, .debit, on: date(2026, 4, 2), normalized: "SWIGGY ORDER", merchant: "Swiggy"),
      row(900, .debit, on: date(2026, 4, 2), normalized: "UBER TRIP", merchant: "Uber"),
    ]

    let merchants = InsightsAggregator.topMerchants(debits, limit: 5)

    XCTAssertEqual(merchants.map(\.label), ["Swiggy", "Uber"])
    XCTAssertEqual(merchants.map(\.totalMinor), [1_000, 900])
  }

  func testMerchantFallsBackToDescriptionWhenThereIsNoMerchantName() {
    let merchants = InsightsAggregator.topMerchants(
      [row(100, .debit, on: date(2026, 4, 1), normalized: "N", merchant: nil, description: "RAW NARRATION")],
      limit: 5
    )
    XCTAssertEqual(merchants.first?.label, "RAW NARRATION")
  }

  func testTopMerchantsRespectsTheLimit() {
    let debits = (1...9).map {
      row($0 * 100, .debit, on: date(2026, 4, 1), normalized: "M\($0)", merchant: "M\($0)")
    }
    XCTAssertEqual(InsightsAggregator.topMerchants(debits, limit: 5).count, 5)
  }

  // MARK: - Trend

  func testTrendBucketsByMonthAndCarriesBothDirections() {
    let rows = [
      row(1_000, .debit, on: date(2026, 3, 31)),
      row(2_000, .debit, on: date(2026, 4, 1)),
      row(50_000, .credit, on: date(2026, 4, 28)),
    ]

    let buckets = InsightsAggregator.trend(rows: rows, calendar: calendar)

    XCTAssertEqual(buckets.count, 2)
    XCTAssertEqual(buckets.map(\.debitMinor), [1_000, 2_000])
    XCTAssertEqual(buckets.map(\.creditMinor), [0, 50_000])
  }

  // MARK: - Accounts

  func testAccountSummariesRollUpPerAccount() {
    let hdfc = UUID()
    let accounts = [
      AccountRef(id: hdfc, displayName: "HDFC", institution: "HDFC Bank", lastFour: "4471", kindRaw: "bank", isArchived: false)
    ]
    let rows = [
      row(50_000, .credit, on: date(2026, 4, 1), account: hdfc),
      row(2_000, .debit, on: date(2026, 4, 5), account: hdfc),
      // No account: belongs to nobody and must not land on HDFC.
      row(9_999, .debit, on: date(2026, 4, 6)),
    ]

    let summaries = InsightsAggregator.accountSummaries(accounts: accounts, rows: rows, includeArchived: false)

    XCTAssertEqual(summaries.count, 1)
    XCTAssertEqual(summaries.first?.trackedBalanceMinor, 48_000)
    XCTAssertEqual(summaries.first?.transactionCount, 2)
    XCTAssertEqual(summaries.first?.trackingSince, date(2026, 4, 1))
  }

  /// `DashboardWiring.accountsIncludeArchived` is `false`, and the AC is
  /// explicit: "archived accounts are excluded from the accounts card".
  func testArchivedAccountsAreExcludedUnlessAskedFor() {
    let archived = UUID()
    let accounts = [
      AccountRef(id: archived, displayName: "Old Card", institution: "ICICI", lastFour: "0001", kindRaw: "card", isArchived: true)
    ]

    XCTAssertTrue(InsightsAggregator.accountSummaries(accounts: accounts, rows: [], includeArchived: false).isEmpty)
    XCTAssertEqual(InsightsAggregator.accountSummaries(accounts: accounts, rows: [], includeArchived: true).count, 1)
  }

  // MARK: - Budgets

  func testBudgetProgressSumsOnlyDebitsInTheCategory() {
    let food = UUID()
    let other = UUID()
    let categories: [UUID: CategoryRef] = [
      food: CategoryRef(id: food, name: "Groceries", paletteSlot: 4)
    ]
    let rows = [
      row(3_000, .debit, on: date(2026, 4, 1), category: food),
      row(1_000, .debit, on: date(2026, 4, 2), category: food),
      row(9_000, .debit, on: date(2026, 4, 2), category: other),
      // A refund into the same category is a credit and is not spend.
      row(500, .credit, on: date(2026, 4, 3), category: food),
    ]

    let progress = InsightsAggregator.budgetProgress(
      budgets: [BudgetRef(categoryID: food, amountMinor: 10_000, isEnabled: true)],
      rows: rows,
      categories: categories,
      periodKey: "2026-04"
    )

    XCTAssertEqual(progress.count, 1)
    XCTAssertEqual(progress.first?.spentMinor, 4_000)
    XCTAssertEqual(progress.first?.fraction ?? 0, 0.4, accuracy: 0.0001)
    XCTAssertEqual(progress.first?.periodKey, "2026-04")
    XCTAssertEqual(progress.first?.categoryName, "Groceries")
  }

  /// Unclamped. `BudgetAlertEvaluator` reads `> 1` as over budget, and
  /// `NomiProgressBar` clamps its own fill — clamping here would make 140% and
  /// 100% indistinguishable to the alert.
  func testFractionIsNotClampedAboveOne() {
    let food = UUID()
    let progress = InsightsAggregator.budgetProgress(
      budgets: [BudgetRef(categoryID: food, amountMinor: 1_000, isEnabled: true)],
      rows: [row(1_400, .debit, on: date(2026, 4, 1), category: food)],
      categories: [:],
      periodKey: "2026-04"
    )
    XCTAssertEqual(progress.first?.fraction ?? 0, 1.4, accuracy: 0.0001)
  }

  /// A disabled budget is not in force. Rendering it at zero would invite an
  /// alert for it, and `BudgetAlertEvaluator` only guards `budgetMinor > 0`.
  func testDisabledBudgetsAreDropped() {
    let food = UUID()
    let progress = InsightsAggregator.budgetProgress(
      budgets: [BudgetRef(categoryID: food, amountMinor: 5_000, isEnabled: false)],
      rows: [row(1_000, .debit, on: date(2026, 4, 1), category: food)],
      categories: [:],
      periodKey: "2026-04"
    )
    XCTAssertTrue(progress.isEmpty)
  }

  func testAZeroBudgetYieldsZeroFractionRatherThanInfinity() {
    let food = UUID()
    let progress = InsightsAggregator.budgetProgress(
      budgets: [BudgetRef(categoryID: food, amountMinor: 0, isEnabled: true)],
      rows: [row(1_000, .debit, on: date(2026, 4, 1), category: food)],
      categories: [:],
      periodKey: "2026-04"
    )
    XCTAssertEqual(progress.first?.fraction, 0)
  }

  func testBudgetProgressIsOrderedMostSpentFirstWithAStableTieBreak() {
    let a = UUID()
    let b = UUID()
    let categories: [UUID: CategoryRef] = [
      a: CategoryRef(id: a, name: "Alpha", paletteSlot: 0),
      b: CategoryRef(id: b, name: "Beta", paletteSlot: 1),
    ]
    let rows = [
      row(500, .debit, on: date(2026, 4, 1), category: a),
      row(500, .debit, on: date(2026, 4, 1), category: b),
    ]
    let budgets = [
      BudgetRef(categoryID: b, amountMinor: 1_000, isEnabled: true),
      BudgetRef(categoryID: a, amountMinor: 1_000, isEnabled: true),
    ]

    let progress = InsightsAggregator.budgetProgress(
      budgets: budgets,
      rows: rows,
      categories: categories,
      periodKey: "2026-04"
    )

    XCTAssertEqual(progress.map(\.categoryName), ["Alpha", "Beta"])
  }
}
