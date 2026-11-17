import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// Insights' period state and reads (S6). Clock-dependent calls take `now`, so
/// each test names the day it is about.
@MainActor
final class ReportsModelTests: XCTestCase {
  private var india: Calendar { NomiCalendar.india }

  private func ist(_ year: Int, _ month: Int, _ day: Int) -> Date {
    india.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }

  private func makeModel(
    store: ReportsModelStore? = nil,
    basis: PeriodBasis = .calendarMonth,
    anchor: Date,
    followsToday: Bool = true
  ) -> ReportsModel {
    ReportsModel(
      insightsStore: store ?? ReportsModelStore(monthly: []),
      basis: basis,
      anchor: anchor,
      followsToday: followsToday,
      calendar: india
    )
  }

  // MARK: - Basis

  /// The R12b follow-up: picking a basis follows today again, from now.
  func testSetBasisResetsFollowsTodayAndAnchorsToNow() {
    let now = ist(2026, 11, 16)
    let model = makeModel(anchor: ist(2026, 8, 10), followsToday: false)

    model.setBasis(.financialYear, now: now)

    XCTAssertEqual(model.basis, .financialYear)
    XCTAssertTrue(model.followsToday)
    XCTAssertEqual(model.anchor, now)
  }

  // MARK: - Midnight refresh

  /// The R12b midnight follow-up: a refresh moves the anchor only while following today.
  func testDayChangedMovesTheAnchorOnlyWhileFollowingToday() {
    let nextDay = ist(2026, 11, 17)

    let following = makeModel(anchor: ist(2026, 11, 16), followsToday: true)
    following.dayChanged(now: nextDay)
    XCTAssertEqual(following.anchor, nextDay)

    let picked = makeModel(anchor: ist(2026, 8, 10), followsToday: false)
    picked.dayChanged(now: nextDay)
    XCTAssertEqual(picked.anchor, ist(2026, 8, 10))
  }

  // MARK: - Picking a period

  func testSelectMonthOpensThePastMonthAndStopsFollowingToday() {
    let now = ist(2026, 11, 16)
    let model = makeModel(basis: .financialYear, anchor: now, followsToday: true)

    model.selectMonth(MonthBucket(id: ist(2026, 8, 1), debitMinor: 0, creditMinor: 0), now: now)

    XCTAssertEqual(model.basis, .calendarMonth)
    XCTAssertEqual(model.period, .month(year: 2026, month: 8))
    XCTAssertFalse(model.followsToday)
  }

  /// A bar that is the current month resumes following the clock.
  func testSelectingTheCurrentMonthFollowsTodayAgain() {
    let now = ist(2026, 11, 16)
    let model = makeModel(anchor: ist(2026, 8, 10), followsToday: false)

    model.selectMonth(MonthBucket(id: ist(2026, 11, 1), debitMinor: 0, creditMinor: 0), now: now)

    XCTAssertTrue(model.followsToday)
    XCTAssertEqual(model.period, .month(year: 2026, month: 11))
  }

  func testPickingAnAnchorFollowsTodayOnlyWhenThePeriodContainsToday() {
    let now = ist(2026, 11, 16)
    let model = makeModel(anchor: now, followsToday: true)

    model.pickAnchor(ist(2026, 8, 10), now: now)
    XCTAssertFalse(model.followsToday)
    XCTAssertEqual(model.period, .month(year: 2026, month: 8))

    model.pickAnchor(now, now: now)
    XCTAssertTrue(model.followsToday)
  }

  // MARK: - Reads

  func testLoadReadsInsightsAndTheMonthlySeriesForTheSelectedPeriod() {
    let store = ReportsModelStore(monthly: [
      MonthBucket(id: ist(2026, 6, 1), debitMinor: 41_000_00, creditMinor: 0),
      MonthBucket(id: ist(2026, 11, 1), debitMinor: 35_000_00, creditMinor: 0),
    ])
    let model = makeModel(store: store, anchor: ist(2026, 11, 16))

    model.load()

    XCTAssertEqual(store.insightsPeriods, [.month(year: 2026, month: 11)])
    XCTAssertEqual(store.monthlyPeriods, [.month(year: 2026, month: 11)])
    guard case .loaded(let figures)? = model.insights else {
      return XCTFail("expected a loaded insights read")
    }
    XCTAssertEqual(figures.debitMinor, 1_000_00)
    guard case .loaded(let buckets)? = model.trend else {
      return XCTFail("expected a loaded trend")
    }
    XCTAssertEqual(buckets.map(\.debitMinor), [41_000_00, 35_000_00])
  }

  /// The financial-year basis reads the year's series, not the month's.
  func testFinancialYearLoadsTheYearsMonthlySeries() {
    let store = ReportsModelStore(monthly: [])
    let model = makeModel(store: store, basis: .financialYear, anchor: ist(2026, 11, 16))

    model.load()

    XCTAssertEqual(store.monthlyPeriods, [.financialYear(startingYear: 2026)])
    XCTAssertEqual(model.period, .financialYear(startingYear: 2026))
  }

  /// A failed read is `.failed`, never an empty load.
  func testFailedReadsAreFailedNotEmpty() {
    let store = ReportsModelStore(monthly: [])
    store.insightsFails = true
    store.monthlyFails = true
    let model = makeModel(store: store, anchor: ist(2026, 11, 16))

    model.load()

    guard case .failed? = model.insights else {
      return XCTFail("expected a failed insights read")
    }
    guard case .failed? = model.trend else {
      return XCTFail("expected a failed trend")
    }
  }

  func testRetryMovesTheLoadToken() {
    let model = makeModel(anchor: ist(2026, 11, 16))
    XCTAssertEqual(model.retryToken, 0)

    model.retry()

    XCTAssertEqual(model.retryToken, 1)
  }
}

/// A stub `InsightsStore` for the model tests. It records every period it is
/// asked for, and can be told to fail either read.
@MainActor
private final class ReportsModelStore: InsightsStore {
  struct Refused: Error {}

  let monthly: [MonthBucket]
  var insightsFails = false
  var monthlyFails = false
  private(set) var insightsPeriods: [InsightPeriod] = []
  private(set) var monthlyPeriods: [InsightPeriod] = []

  init(monthly: [MonthBucket]) {
    self.monthly = monthly
  }

  func insights(for period: InsightPeriod) throws -> PeriodInsights {
    insightsPeriods.append(period)
    if insightsFails { throw Refused() }
    return PeriodInsights(
      period: period,
      debitMinor: 1_000_00,
      creditMinor: 2_000_00,
      netMinor: 1_000_00,
      priorDebitMinor: nil,
      priorCreditMinor: nil,
      transactionCount: 1,
      byDay: [],
      byCategory: [],
      topMerchants: [],
      needsReviewCount: 0,
      uncategorizedCount: 0
    )
  }

  func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket] {
    monthlyPeriods.append(period)
    if monthlyFails { throw Refused() }
    return monthly
  }

  func trend(months: Int) throws -> [MonthBucket] { [] }
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { [] }
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { [] }
  func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { [] }
}
