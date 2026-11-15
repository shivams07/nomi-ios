import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// R12a, I-4. `monthlyTrend(for:)` through a real in-memory container, so the
/// fetch window, the transfer exclusion and the zero-fill are all exercised.
/// Pinned to Asia/Kolkata, and "now" is 14 Nov 2026 at 09:00 IST unless a test
/// moves it.
@MainActor
final class MonthlyTrendTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  /// A clock the store reads, so one test can move the day forward.
  private final class Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
  }

  /// The fixture from I-4: 5 Jun ₹100 debit, 20 Aug ₹200 debit, 3 Nov ₹50 credit.
  private func fixture() throws -> (store: SwiftDataInsightsStore, clock: Clock, context: ModelContext) {
    let context = try makeContext()
    context.insert(Transaction(date: date(2026, 6, 5), amountMinor: 10_000, directionRaw: Direction.debit.rawValue))
    context.insert(Transaction(date: date(2026, 8, 20), amountMinor: 20_000, directionRaw: Direction.debit.rawValue))
    context.insert(Transaction(date: date(2026, 11, 3), amountMinor: 5_000, directionRaw: Direction.credit.rawValue))
    try context.save()

    let clock = Clock(date(2026, 11, 14, 9))
    let store = SwiftDataInsightsStore(
      context: context, cache: InsightsCache(), calendar: calendar, now: { clock.now })
    return (store, clock, context)
  }

  /// `"Mon debitRupees/creditRupees"`, the form the I-4 table is written in.
  private func labels(_ buckets: [MonthBucket]) -> [String] {
    let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return buckets.map { bucket in
      let month = calendar.component(.month, from: bucket.id)
      return "\(names[month - 1]) \(bucket.debitMinor / 100)/\(bucket.creditMinor / 100)"
    }
  }

  func testTheSixMonthsEndingWithNovember() throws {
    let (store, _, _) = try fixture()
    let buckets = try store.monthlyTrend(for: .month(year: 2026, month: 11))
    XCTAssertEqual(
      labels(buckets),
      ["Jun 100/0", "Jul 0/0", "Aug 200/0", "Sep 0/0", "Oct 0/0", "Nov 0/50"])
  }

  func testTheFinancialYearIsEightBucketsWithNoDecemberToMarch() throws {
    let (store, _, _) = try fixture()
    let buckets = try store.monthlyTrend(for: .financialYear(startingYear: 2026))
    XCTAssertEqual(
      labels(buckets),
      ["Apr 0/0", "May 0/0", "Jun 100/0", "Jul 0/0", "Aug 200/0", "Sep 0/0", "Oct 0/0", "Nov 0/50"])
  }

  /// A year with no rows is still twelve buckets, April 2025 to March 2026.
  func testAPriorFinancialYearWithNoRowsIsTwelveEmptyBuckets() throws {
    let (store, _, _) = try fixture()
    let buckets = try store.monthlyTrend(for: .financialYear(startingYear: 2025))
    XCTAssertEqual(buckets.count, 12)
    XCTAssertEqual(buckets.first?.id, date(2025, 4, 1, 0))
    XCTAssertEqual(buckets.last?.id, date(2026, 3, 1, 0))
    XCTAssertEqual(
      labels(buckets),
      [
        "Apr 0/0", "May 0/0", "Jun 0/0", "Jul 0/0", "Aug 0/0", "Sep 0/0",
        "Oct 0/0", "Nov 0/0", "Dec 0/0", "Jan 0/0", "Feb 0/0", "Mar 0/0",
      ])
  }

  func testAllTimeHasNoBuckets() throws {
    let (store, _, _) = try fixture()
    XCTAssertEqual(try store.monthlyTrend(for: .allTime).count, 0)
  }

  /// A month that starts after today is not a bucket. December 2026 starts
  /// after 14 November, so the six months ending in it are five buckets here.
  func testAMonthThatHasNotStartedIsNotInTheTrend() throws {
    let (store, _, _) = try fixture()
    let buckets = try store.monthlyTrend(for: .month(year: 2026, month: 12))
    XCTAssertEqual(labels(buckets), ["Jul 0/0", "Aug 200/0", "Sep 0/0", "Oct 0/0", "Nov 0/50"])
  }

  /// DEC-05. A transfer leg is in no bucket, as the trend has always excluded it.
  func testATransferRowIsInNoBucket() throws {
    let context = try makeContext()
    let now = date(2026, 11, 14, 9)
    context.insert(Transaction(date: date(2026, 8, 20), amountMinor: 20_000, directionRaw: Direction.debit.rawValue))
    context.insert(Transaction(
      date: date(2026, 8, 15), amountMinor: 100_000, directionRaw: Direction.debit.rawValue,
      transferGroupID: UUID()))
    try context.save()

    let store = SwiftDataInsightsStore(
      context: context, cache: InsightsCache(), calendar: calendar, now: { now })
    let buckets = try store.monthlyTrend(for: .month(year: 2026, month: 11))
    XCTAssertEqual(labels(buckets)[2], "Aug 200/0", "the ₹1,000 transfer is not spend")
  }

  /// Rows after today are not in the trend, though they sit in the last month
  /// of the window. Today is 14 November, so 15 November is out.
  func testARowDatedAfterTodayIsNotCounted() throws {
    let context = try makeContext()
    let now = date(2026, 11, 14, 9)
    context.insert(Transaction(date: date(2026, 11, 15, 10), amountMinor: 70_000, directionRaw: Direction.debit.rawValue))
    try context.save()

    let store = SwiftDataInsightsStore(
      context: context, cache: InsightsCache(), calendar: calendar, now: { now })
    let buckets = try store.monthlyTrend(for: .month(year: 2026, month: 11))
    XCTAssertEqual(labels(buckets).last, "Nov 0/0")
  }

  /// The trend is cached like every aggregate, and a value cached on one day is
  /// not served on the next. The row is a direct insert, which does not
  /// invalidate, so the only thing that can move the figure is the day change.
  func testAValueComputedYesterdayIsNotServedToday() throws {
    let (store, clock, context) = try fixture()
    XCTAssertEqual(labels(try store.monthlyTrend(for: .month(year: 2026, month: 11))).last, "Nov 0/50")

    context.insert(Transaction(date: date(2026, 11, 14, 12), amountMinor: 1_000, directionRaw: Direction.debit.rawValue))
    try context.save()
    XCTAssertEqual(
      labels(try store.monthlyTrend(for: .month(year: 2026, month: 11))).last, "Nov 0/50",
      "same day: still the cached value")

    clock.now = date(2026, 11, 15, 9)
    XCTAssertEqual(
      labels(try store.monthlyTrend(for: .month(year: 2026, month: 11))).last, "Nov 10/50",
      "new day: recomputed, and the 14 November row is in it")
  }

  private func makeContext() throws -> ModelContext {
    let stack = try InMemoryStack(schema: Schema([Transaction.self, NomiCore.Category.self]))
    stacks.append(stack)
    return stack.context
  }
}
