import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// U17a, store side. The rule itself is tested over value types in
/// `RecurrenceDetectorTests`; what is left to prove here is the part that needs
/// a database — the window, the direction narrowing, and the cache.
///
/// A `ModelContainer` under `swift test` is fine in XCTest and traps under
/// swift-testing (see `InMemoryModelContainer`), which is why this is XCTest,
/// like `RecentTransactionsTests` next to it.
@MainActor
final class RecurringStoreTests: XCTestCase {

  func testAMonthlyChargeIsReportedWithItsNextDate() throws {
    let (store, context, _) = try makeStore()
    insertRun(daysAgo: [60, 30, 0], into: context)

    let series = try store.recurringSeries()

    XCTAssertEqual(series.count, 1)
    XCTAssertEqual(series.first?.id, "NETFLIX")
    XCTAssertEqual(series.first?.occurrences, 3)
    XCTAssertEqual(series.first?.amountMinor, 49900)
    XCTAssertEqual(series.first?.nextExpected, date(daysAgo: -30), "the last charge plus the median gap")
  }

  /// R14's rule, and the reason this store shares `InsightsCache` rather than
  /// holding its own: detection is a grouping over every debit in six months,
  /// and the dashboard renders many times per write.
  func testTheSecondCallIsACacheHitAndAWriteDropsIt() throws {
    let (store, context, cache) = try makeStore()
    insertRun(daysAgo: [60, 30, 0], into: context)

    let first = try store.recurringSeries()
    let missesAfterFirst = cache.missCount
    let second = try store.recurringSeries()

    XCTAssertEqual(cache.missCount, missesAfterFirst, "the second call is a hit")
    XCTAssertEqual(first, second)

    cache.invalidate()
    _ = try store.recurringSeries()
    XCTAssertEqual(cache.missCount, missesAfterFirst + 1, "a write drops it")
  }

  /// The row written after the first read is the point of the invalidation: a
  /// fourth charge changes `occurrences` and `nextExpected`, and the card must
  /// not keep showing yesterday's answer.
  func testAChargeWrittenAfterAReadShowsUpOnceTheCacheIsCleared() throws {
    let (store, context, cache) = try makeStore()
    insertRun(daysAgo: [90, 60, 30], into: context)
    let before = try store.recurringSeries()
    XCTAssertEqual(before.first?.occurrences, 3)

    insertRun(daysAgo: [0], into: context)
    WriteCoordinator(cache: cache).didWrite()

    let after = try store.recurringSeries()
    XCTAssertEqual(after.first?.occurrences, 4)
    XCTAssertEqual(after.first?.nextExpected, date(daysAgo: -30))
  }

  /// The window is six months and it is the store's, not the caller's. A run
  /// that ended before it does not come back — which is also the honest cost of
  /// the window: a subscription needs three charges *inside* six months, so one
  /// with only two in range is invisible even though the ledger holds five.
  func testARunEntirelyOlderThanTheWindowIsNotRead() throws {
    let (store, context, _) = try makeStore()
    insertRun(daysAgo: [260, 230, 200], into: context)

    XCTAssertTrue(try store.recurringSeries().isEmpty)
  }

  func testARunWithOnlyTwoChargesInsideTheWindowIsNotReported() throws {
    let (store, context, _) = try makeStore()
    insertRun(daysAgo: [220, 190, 160, 130], into: context)

    XCTAssertTrue(try store.recurringSeries().isEmpty)
  }

  /// Salary is the most regular run in any ledger. The fetch predicate excludes
  /// credits before the detector ever sees them; a test on this side can only
  /// prove the outcome, not the SQL, so it does not claim to.
  func testACreditRunIsNotReported() throws {
    let (store, context, _) = try makeStore()
    for days in [60, 30, 0] {
      context.insert(
        Transaction(
          date: date(daysAgo: days),
          descriptionText: "SALARY ACME",
          normalizedDescription: "SALARY ACME",
          amountMinor: 8_000_000,
          directionRaw: Direction.credit.rawValue))
    }
    try context.save()

    XCTAssertTrue(try store.recurringSeries().isEmpty)
  }

  /// W1-13 (M3). A dollar subscription is still a subscription, but its amount
  /// is cents and every figure on the insights screens is rupees. Excluded in
  /// the fetch, as credits are, so the detector never sees it.
  func testAForeignRunIsNotReported() throws {
    let (store, context, _) = try makeStore()
    for days in [60, 30, 0] {
      context.insert(
        Transaction(
          date: date(daysAgo: days),
          descriptionText: "SPOTIFY USA",
          merchantName: "Spotify",
          normalizedDescription: "SPOTIFY USA",
          amountMinor: 1_199,
          currencyCode: "USD"))
    }
    try context.save()

    XCTAssertTrue(try store.recurringSeries().isEmpty)
  }

  func testAnEmptyLedgerIsAnEmptyAnswerNotAnError() throws {
    let (store, _, _) = try makeStore()

    XCTAssertTrue(try store.recurringSeries().isEmpty)
  }

  // MARK: -

  /// A fixed instant - 24 April 2026, 08:36 IST - paired with a fixed IST
  /// calendar, so the six-month window does not move with the CI machine's
  /// time zone or with the hour the run happens to start.
  private let reference = Date(timeIntervalSince1970: 1_777_000_000)

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private func date(daysAgo days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: reference)!
  }

  private func insertRun(daysAgo days: [Int], into context: ModelContext) {
    for day in days {
      context.insert(
        Transaction(
          date: date(daysAgo: day),
          descriptionText: "NETFLIX SUBSCRIPTION",
          merchantName: "Netflix",
          normalizedDescription: "NETFLIX",
          amountMinor: 49900))
    }
    try? context.save()
  }

  private func makeStore() throws -> (SwiftDataRecurringStore, ModelContext, InsightsCache) {
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
    // Copied out rather than captured through `self`: the closure outlives
    // this call and there is no reason for the store to hold the test case.
    let moment = reference
    let store = SwiftDataRecurringStore(
      context: context,
      cache: cache,
      calendar: calendar,
      now: { moment })
    return (store, context, cache)
  }
}
