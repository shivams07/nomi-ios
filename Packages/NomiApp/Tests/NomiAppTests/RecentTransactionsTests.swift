import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// F2. The dashboard's recent card needs five rows. It used to get them from
/// `transactions(in: .allTime)`, so the first read after every write pulled the
/// entire ledger across the SwiftData boundary and threw all but five away.
///
/// `recentTransactions(limit:)` is a `fetchLimit`. What a test on this side can
/// actually prove is the contract - newest first, at most `limit`, and cached
/// like every other aggregate. It cannot see the SQL, so it does not claim to.
///
/// A `ModelContainer` under `swift test` is fine in XCTest and traps under
/// swift-testing (see `InMemoryModelContainer`), which is why this is XCTest,
/// like `AccountStoreTests` next to it.
@MainActor
final class RecentTransactionsTests: XCTestCase {

  func testRecentReturnsTheNewestRowsNewestFirst() throws {
    let (store, context, _) = try makeStore()
    let dates = insertRows(count: 20, into: context)

    let recent = try store.recentTransactions(limit: 5)

    XCTAssertEqual(recent.count, 5)
    XCTAssertEqual(recent.map(\.date), Array(dates.sorted(by: >).prefix(5)))
    XCTAssertEqual(
      recent.map(\.date), recent.map(\.date).sorted(by: >),
      "newest first")
  }

  func testRecentDoesNotMaterialiseMoreRowsThanAsked() throws {
    let (store, context, _) = try makeStore()
    _ = insertRows(count: 20, into: context)

    XCTAssertEqual(try store.recentTransactions(limit: 1).count, 1)
    XCTAssertEqual(try store.recentTransactions(limit: 20).count, 20)
    XCTAssertEqual(
      try store.recentTransactions(limit: 50).count, 20,
      "a limit past the end is not an error")
    XCTAssertTrue(try store.recentTransactions(limit: 0).isEmpty)
  }

  func testRecentIsCachedPerLimitAndClearedOnWrite() throws {
    let (store, context, cache) = try makeStore()
    _ = insertRows(count: 20, into: context)

    _ = try store.recentTransactions(limit: 5)
    let missesAfterFirst = cache.missCount
    _ = try store.recentTransactions(limit: 5)
    XCTAssertEqual(cache.missCount, missesAfterFirst, "the second read is a hit")

    _ = try store.recentTransactions(limit: 3)
    XCTAssertEqual(
      cache.missCount, missesAfterFirst + 1,
      "a different limit is a different key, not a stale five-row answer")

    cache.invalidate()
    _ = try store.recentTransactions(limit: 5)
    XCTAssertEqual(cache.missCount, missesAfterFirst + 2, "a write drops it")
  }

  /// The behaviour the dashboard depends on: rows written after the first read
  /// show up, because `WriteCoordinator` clears the cache.
  func testANewestRowWrittenAfterAReadAppearsOnceTheCacheIsCleared() throws {
    let (store, context, cache) = try makeStore()
    _ = insertRows(count: 20, into: context)
    let before = try store.recentTransactions(limit: 5)

    let newest = Transaction(
      date: Date(timeIntervalSince1970: 2_000_000_000),
      descriptionText: "NEWEST",
      amountMinor: 999_00)
    context.insert(newest)
    try context.save()
    WriteCoordinator(cache: cache).didWrite()

    let after = try store.recentTransactions(limit: 5)
    XCTAssertNotEqual(before.map(\.id), after.map(\.id))
    XCTAssertEqual(after.first?.id, newest.id)
  }

  // MARK: -

  /// Descending ids so a store that returned insertion order, or id order,
  /// would not accidentally agree with date order.
  @discardableResult
  private func insertRows(count: Int, into context: ModelContext) -> [Date] {
    var dates: [Date] = []
    for index in 0..<count {
      let date = Date(timeIntervalSince1970: 1_700_000_000 + Double((count - index) * 86_400))
      dates.append(date)
      context.insert(
        Transaction(
          date: date,
          descriptionText: "ROW \(index)",
          amountMinor: 100 + index))
    }
    try? context.save()
    return dates
  }

  private func makeStore() throws -> (SwiftDataInsightsStore, ModelContext, InsightsCache) {
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
    let cache = InsightsCache()
    return (SwiftDataInsightsStore(context: context, cache: cache), context, cache)
  }
}
