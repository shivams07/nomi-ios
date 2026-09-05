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

  // MARK: - F4: the cache is bounded

  /// It was unbounded. Only `invalidate()` ever freed anything, so a session
  /// spent scrubbing backwards through Reports grew one entry per month for as
  /// long as the app stayed up.
  func testTheCacheStopsGrowingAtItsCapacity() {
    let cache = InsightsCache()

    for month in 1...(InsightsCache.capacity + 1) {
      _ = cache.value(for: .insights(.month(year: 2020 + month / 12, month: month))) { month }
    }

    XCTAssertEqual(cache.count, InsightsCache.capacity)
    XCTAssertEqual(
      cache.missCount, InsightsCache.capacity + 1,
      "every read was a miss; nothing was served from the cache")
  }

  /// Oldest-first, and the evicted one is gone rather than stale: reading it
  /// again is a miss, while the entry inserted right after it is still a hit.
  ///
  /// Order matters in the assertions below - reading the evicted key puts it
  /// back and evicts the next-oldest - so the survivor is checked first.
  func testTheFirstInsertedEntryIsTheOneEvicted() {
    let cache = InsightsCache()
    let first = InsightsCacheKey.insights(.month(year: 2024, month: 1))

    _ = cache.value(for: first) { 1 }
    for month in 2...(InsightsCache.capacity + 1) {
      _ = cache.value(for: .insights(.month(year: 2020 + month / 12, month: month))) { month }
    }

    let second = InsightsCacheKey.insights(.month(year: 2020, month: 2))
    let missesBeforeSurvivor = cache.missCount
    _ = cache.value(for: second) { 2 }
    XCTAssertEqual(
      cache.missCount, missesBeforeSurvivor,
      "the entry inserted second is still held")

    let missesBeforeEvicted = cache.missCount
    _ = cache.value(for: first) { 1 }
    XCTAssertEqual(
      cache.missCount, missesBeforeEvicted + 1,
      "the entry inserted first was evicted")
  }

  /// LRU, not FIFO. A key read on every render must not be the first one
  /// dropped - that is the entry the cache exists for.
  func testAHitRefreshesRecencySoTheHotKeySurvives() {
    let cache = InsightsCache()
    let hot = InsightsCacheKey.insights(.month(year: 2024, month: 1))

    _ = cache.value(for: hot) { 1 }
    // Fill to exactly capacity, touching `hot` as a screen re-rendering would.
    for month in 2...InsightsCache.capacity {
      _ = cache.value(for: .insights(.month(year: 2020 + month / 12, month: month))) { month }
      _ = cache.value(for: hot) { 1 }
    }
    // One more, which must evict something.
    _ = cache.value(for: .trend(months: 99)) { [MonthBucket]() }

    let missesBefore = cache.missCount
    _ = cache.value(for: hot) { 1 }
    XCTAssertEqual(cache.missCount, missesBefore, "the hot key is still cached")
    XCTAssertEqual(cache.count, InsightsCache.capacity)
  }

  /// `.transactions` entries hold live `@Model` references - an `.allTime`
  /// entry pins the whole ledger - so they get their own, much tighter bound.
  func testTransactionEntriesAreCappedFarBelowTheGeneralBound() {
    let cache = InsightsCache()
    let periods: [InsightPeriod] = [
      .allTime, .month(year: 2026, month: 1), .month(year: 2026, month: 2),
      .month(year: 2026, month: 3), .month(year: 2026, month: 4),
    ]

    for period in periods {
      _ = cache.value(for: .transactions(period)) { [Transaction]() }
    }

    XCTAssertEqual(cache.count, InsightsCache.transactionCapacity)

    let missesBefore = cache.missCount
    _ = cache.value(for: .transactions(.allTime)) { [Transaction]() }
    XCTAssertEqual(cache.missCount, missesBefore + 1, "the oldest ledger read was dropped")
  }

  /// The tight `.transactions` bound must not reach across and evict the
  /// aggregates the screen around it is mid-render on.
  func testTransactionEvictionLeavesOtherKindsAlone() {
    let cache = InsightsCache()
    let aggregate = InsightsCacheKey.insights(.month(year: 2026, month: 4))

    _ = cache.value(for: aggregate) { 42 }
    for month in 1...5 {
      _ = cache.value(for: .transactions(.month(year: 2026, month: month))) { [Transaction]() }
    }

    let missesBefore = cache.missCount
    _ = cache.value(for: aggregate) { 42 }
    XCTAssertEqual(cache.missCount, missesBefore, "the aggregate survived")
    XCTAssertEqual(cache.count, InsightsCache.transactionCapacity + 1)
  }

  func testInvalidationClearsTheRecencyOrderTooSoTheBoundIsNotInheritedStale() {
    let cache = InsightsCache()
    for month in 1...InsightsCache.capacity {
      _ = cache.value(for: .insights(.month(year: 2020 + month / 12, month: month))) { month }
    }

    cache.invalidate()
    XCTAssertTrue(cache.isEmpty)
    XCTAssertEqual(cache.count, 0)

    for month in 1...InsightsCache.capacity {
      _ = cache.value(for: .insights(.month(year: 2020 + month / 12, month: month))) { month }
    }
    XCTAssertEqual(cache.count, InsightsCache.capacity, "nothing was evicted early")
  }
}
