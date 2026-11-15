import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// I-10. `priorByDay` is `byDay` of the like-for-like prior window, read through
/// the same `priorRange` the store already uses for the prior totals.
///
/// The store tests run through `SwiftDataInsightsStore`, with `now` pinned to
/// 14 November 2026, because the like-for-like cut depends on the anchor date and
/// a pure test would have to be handed the window rather than derive it. The
/// stack is held in a stored property (see `InMemoryStack`).
@MainActor
final class PriorByDayTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    components.timeZone = calendar.timeZone
    return calendar.date(from: components)!
  }

  /// A bucket's id is the start of its day.
  private func dayID(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.startOfDay(for: date(year, month, day))
  }

  private func makeStore(now: Date) throws -> (SwiftDataInsightsStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let store = SwiftDataInsightsStore(
      context: stack.context, cache: InsightsCache(), calendar: calendar, now: { now })
    return (store, stack.context)
  }

  private func row(_ amountMinor: Int, _ direction: Direction, on date: Date, currency: String = "INR", transfer: Bool = false) -> LedgerRow {
    LedgerRow(
      id: UUID(), date: date, amountMinor: amountMinor, directionRaw: direction.rawValue,
      categoryID: nil, accountID: nil, normalizedDescription: "MERCHANT", merchantName: nil,
      descriptionText: "raw", needsReview: false, currencyCode: currency, isTransfer: transfer)
  }

  /// The done-when. Anchor 14 November: the prior window is 1 to 14 October, so
  /// the row on the 15th and the credit on the 31st are outside it.
  func testPriorByDayCoversTheLikeForLikeDaysOnly() throws {
    let (store, context) = try makeStore(now: date(2026, 11, 14))
    context.insert(Transaction(date: date(2026, 10, 1), amountMinor: 100))
    context.insert(Transaction(date: date(2026, 10, 14), amountMinor: 200))
    context.insert(Transaction(date: date(2026, 10, 15), amountMinor: 400))
    context.insert(
      Transaction(date: date(2026, 10, 31), amountMinor: 800, directionRaw: Direction.credit.rawValue))
    try context.save()

    let insights = try store.insights(for: .month(year: 2026, month: 11))

    XCTAssertEqual(insights.priorByDay.map(\.id), [dayID(2026, 10, 1), dayID(2026, 10, 14)])
    XCTAssertEqual(insights.priorByDay.map(\.debitMinor), [100, 200])
  }

  /// A period that is not the current month has no part of itself to cut, so
  /// its prior window is the whole of the month before: 1 to 30 September.
  func testPriorByDayIsTheWholePriorMonthWhenThePeriodIsNotCurrent() throws {
    let (store, context) = try makeStore(now: date(2026, 11, 14))
    context.insert(Transaction(date: date(2026, 9, 1), amountMinor: 100))
    context.insert(Transaction(date: date(2026, 9, 30), amountMinor: 300))
    try context.save()

    let insights = try store.insights(for: .month(year: 2026, month: 10))

    XCTAssertEqual(insights.priorByDay.map(\.id), [dayID(2026, 9, 1), dayID(2026, 9, 30)])
  }

  /// `.allTime` has no prior window, so there is nothing to compare against and
  /// the list is empty rather than a copy of the period.
  func testPriorByDayIsEmptyForAllTime() throws {
    let (store, context) = try makeStore(now: date(2026, 11, 14))
    context.insert(Transaction(date: date(2026, 10, 5), amountMinor: 100))
    try context.save()

    XCTAssertTrue(try store.insights(for: .allTime).priorByDay.isEmpty)
  }

  /// No prior rows handed in (the store's `.allTime` case) is an empty list,
  /// with nothing else in the aggregator affected.
  func testPriorByDayIsEmptyWhenNoPriorRowsAreGiven() {
    let insights = InsightsAggregator.insights(
      period: .allTime,
      rows: [row(100, .debit, on: date(2026, 11, 3))],
      categories: [:],
      priorRows: nil,
      calendar: calendar
    )

    XCTAssertTrue(insights.priorByDay.isEmpty)
    XCTAssertNil(insights.priorDebitMinor)
  }

  /// The same counted-rows rule as the current period: a transfer and a foreign
  /// row in the prior window are out, and a credit-only day is a bucket.
  func testPriorByDayFollowsTheCountedRowsRule() {
    let priorRows = [
      row(100, .debit, on: date(2026, 10, 3)),
      row(50, .credit, on: date(2026, 10, 3)),
      row(999, .debit, on: date(2026, 10, 4), transfer: true),
      row(777, .debit, on: date(2026, 10, 5), currency: "USD"),
      row(25, .credit, on: date(2026, 10, 6)),
    ]

    let insights = InsightsAggregator.insights(
      period: .month(year: 2026, month: 11),
      rows: [],
      categories: [:],
      priorRows: priorRows,
      calendar: calendar
    )

    XCTAssertEqual(insights.priorByDay.map(\.id), [dayID(2026, 10, 3), dayID(2026, 10, 6)])
    XCTAssertEqual(insights.priorByDay.map(\.debitMinor), [100, 0])
    XCTAssertEqual(insights.priorByDay.map(\.creditMinor), [50, 25])
  }
}
