import NomiCore
import XCTest

@testable import NomiApp

/// R14's "cached per period and invalidated on write". The behaviour is
/// invisible from outside — a cached read and a fresh one return the same value
/// — so `missCount` exists to make it assertable.
@MainActor
final class InsightsCacheTests: XCTestCase {

  func testFirstReadMissesAndSecondReadHits() {
    let cache = InsightsCache()
    var computed = 0

    for _ in 0..<3 {
      _ = cache.value(for: .insights(.month(year: 2026, month: 4))) { () -> Int in
        computed += 1
        return 42
      }
    }

    XCTAssertEqual(computed, 1)
    XCTAssertEqual(cache.missCount, 1)
  }

  /// `InsightPeriod` is value-addressed — `month(year:month:)` rather than
  /// `month(anchor: Date)` — precisely so the same month is the same key
  /// (design §2.3). A `Date` anchor would produce a different key every second
  /// and the cache would never hit.
  func testTheSameMonthIsTheSameKey() {
    let cache = InsightsCache()
    var computed = 0

    _ = cache.value(for: .insights(.month(year: 2026, month: 4))) { () -> Int in
      computed += 1
      return 1
    }
    _ = cache.value(for: .insights(.month(year: 2026, month: 4))) { () -> Int in
      computed += 1
      return 1
    }

    XCTAssertEqual(computed, 1)
  }

  func testDifferentPeriodsAreDifferentEntries() {
    let cache = InsightsCache()

    _ = cache.value(for: .insights(.month(year: 2026, month: 4))) { 1 }
    _ = cache.value(for: .insights(.month(year: 2026, month: 5))) { 2 }
    _ = cache.value(for: .trend(months: 6)) { [MonthBucket]() }
    _ = cache.value(for: .accountSummaries(includeArchived: true)) { [AccountSummary]() }
    _ = cache.value(for: .accountSummaries(includeArchived: false)) { [AccountSummary]() }
    _ = cache.value(for: .budgetProgress(year: 2026, month: 4)) { [BudgetProgress]() }

    XCTAssertEqual(cache.missCount, 6)
  }

  func testInvalidationDropsEverything() {
    let cache = InsightsCache()
    _ = cache.value(for: .insights(.allTime)) { 1 }
    _ = cache.value(for: .trend(months: 6)) { 2 }
    XCTAssertEqual(cache.missCount, 2)

    cache.invalidate()

    _ = cache.value(for: .insights(.allTime)) { 1 }
    _ = cache.value(for: .trend(months: 6)) { 2 }
    XCTAssertEqual(cache.missCount, 4)
    XCTAssertEqual(cache.invalidationCount, 1)
  }

  /// The generation is what redraws the dashboard, the reports page and the
  /// ledger after a background sync. None of them hold a `@Query`, so SwiftData's
  /// own change tracking never reaches them.
  func testGenerationAdvancesOnEveryInvalidation() {
    let cache = InsightsCache()
    XCTAssertEqual(cache.generation, 0)

    cache.invalidate()
    cache.invalidate()

    XCTAssertEqual(cache.generation, 2)
  }

  /// An invalidation with nothing cached must still publish. A write that lands
  /// before the first read is the ordinary case at launch, and swallowing it
  /// leaves a view that never redraws.
  func testInvalidatingAnEmptyCacheStillPublishes() {
    let cache = InsightsCache()
    cache.invalidate()
    XCTAssertEqual(cache.generation, 1)
  }

  func testAThrowingComputeIsNotCached() {
    struct Boom: Error {}
    let cache = InsightsCache()

    XCTAssertThrowsError(try cache.value(for: .insights(.allTime)) { () throws -> Int in throw Boom() })
    XCTAssertTrue(cache.isEmpty)
  }
}
