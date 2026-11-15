import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `ReportsScreen.monthlyTrend` read on a view that is not in a hierarchy (T2a).
/// `@State` answers with its initial value there, which these tests rely on. If
/// that stops being true, the first test sees `requestedPeriods == []`.
@MainActor
final class ReportsWiringTests: XCTestCase {
  private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  /// 2025-08-15 12:00, in the financial year that starts April 2025.
  private var anchor: Date {
    utc.date(from: DateComponents(year: 2025, month: 8, day: 15, hour: 12))!
  }

  /// Twelve buckets from April 2025, ids on the first of each month.
  private var monthlyBuckets: [MonthBucket] {
    (0..<12).map { offset in
      let month = (3 + offset) % 12 + 1
      let year = 2025 + (3 + offset) / 12
      let id = utc.date(from: DateComponents(year: year, month: month, day: 1))!
      return MonthBucket(id: id, debitMinor: 1_000_00 * (offset + 1), creditMinor: 0)
    }
  }

  /// Answers `monthlyTrend(for:)` with `monthly` and records each request. It
  /// counts `trend(months:)` calls, which the mutant reads instead.
  @MainActor
  private final class ReportsWiringStore: InsightsStore {
    struct Unused: Error {}
    struct Refused: Error {}

    let monthly: [MonthBucket]
    var failsMonthly = false
    private(set) var requestedPeriods: [InsightPeriod] = []
    private(set) var trendCalls = 0

    init(monthly: [MonthBucket]) {
      self.monthly = monthly
    }

    func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket] {
      requestedPeriods.append(period)
      if failsMonthly { throw Refused() }
      return monthly
    }

    func trend(months: Int) throws -> [MonthBucket] {
      trendCalls += 1
      return []
    }

    func insights(for period: InsightPeriod) throws -> PeriodInsights { throw Unused() }
    func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] { throw Unused() }
    func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] { throw Unused() }
    func transactions(in period: InsightPeriod) throws -> [NomiCore.Transaction] { throw Unused() }
  }

  /// The financial-year basis reads its bars from `monthlyTrend(for:)`, for the
  /// selected period, and not from `trend(months:)`. Kills T2-M10.
  func testFinancialYearBarsReadMonthlyTrend() throws {
    let store = ReportsWiringStore(monthly: monthlyBuckets)
    let screen = ReportsScreen(insightsStore: store, initialBasis: .financialYear, initialAnchor: anchor)

    let trend = try XCTUnwrap(screen.monthlyTrend)
    guard case .loaded(let buckets) = trend else {
      return XCTFail("expected .loaded, got a failed or missing read")
    }

    XCTAssertEqual(buckets.map(\.id), monthlyBuckets.map(\.id))
    XCTAssertEqual(store.requestedPeriods, [.financialYear(startingYear: 2025)])
    XCTAssertEqual(store.trendCalls, 0)
  }

  /// The calendar basis draws daily bars from the period itself, so it reads no
  /// monthly series at all.
  func testCalendarMonthReadsNoMonthlySeries() {
    let store = ReportsWiringStore(monthly: monthlyBuckets)
    let screen = ReportsScreen(insightsStore: store, initialBasis: .calendarMonth, initialAnchor: anchor)

    XCTAssertNil(screen.monthlyTrend)
    XCTAssertEqual(store.requestedPeriods, [])
  }

  /// A read that threw is `.failed`, not an empty series.
  func testMonthlyReadFailureIsFailedNotEmpty() throws {
    let store = ReportsWiringStore(monthly: monthlyBuckets)
    store.failsMonthly = true
    let screen = ReportsScreen(insightsStore: store, initialBasis: .financialYear, initialAnchor: anchor)

    let trend = try XCTUnwrap(screen.monthlyTrend)
    guard case .failed = trend else {
      return XCTFail("expected .failed, got .loaded")
    }
  }
}
