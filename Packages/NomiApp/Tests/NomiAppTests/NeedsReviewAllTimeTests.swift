import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp
@testable import NomiUI

/// D26. Home's Needs-you count is the Ledger's Needs review chip: every flagged
/// row, in any month. `needsReviewCountAllTime()` is that count. The period's
/// own `needsReviewCount` (from `insights(for:)`) is left as it was, for the
/// figures that are still per period.
///
/// XCTest, like its neighbours, because the container has to outlive the store
/// (see `InMemoryStack`).
@MainActor
final class NeedsReviewAllTimeTests: XCTestCase {

  /// Owns each test's container for the life of the test. See `InMemoryStack`.
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  /// Fixed, so the store's own period is the same in every test.
  private let now = Date(timeIntervalSince1970: 1_804_000_000)

  private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
  }

  /// Flagged and unflagged plain rows on one day. Plain debits, no transfer,
  /// so the period's own count and the all-time count meet on the same rows.
  private func insert(flagged: Int, unflagged: Int = 0, on day: Date, into context: ModelContext) {
    for index in 0..<flagged {
      context.insert(
        NomiCore.Transaction(
          date: day, descriptionText: "FLAGGED \(index)", amountMinor: 100 + index, needsReview: true))
    }
    for index in 0..<unflagged {
      context.insert(
        NomiCore.Transaction(
          date: day, descriptionText: "CLEAR \(index)", amountMinor: 500 + index, needsReview: false))
    }
  }

  // MARK: - The count is not the period's

  /// Flagged rows in three months. The October period holds three of them, and
  /// all time holds six. Home's card must read six, the chip's count.
  func testAllTimeCountIgnoresThePeriod() throws {
    let (store, context) = try makeStore()
    insert(flagged: 2, unflagged: 4, on: date(2026, 9), into: context)
    insert(flagged: 3, unflagged: 1, on: date(2026, 10), into: context)
    insert(flagged: 1, on: date(2026, 11), into: context)
    try context.save()

    XCTAssertEqual(
      try store.insights(for: .month(year: 2026, month: 10)).needsReviewCount, 3,
      "the period's own count is still the period's")
    XCTAssertEqual(
      try store.needsReviewCountAllTime(), 6,
      "the all-time count is every flagged row, whatever the month")
  }

  /// A month with no flagged rows still shows the flagged rows from other months.
  func testAllTimeCountIsNonZeroInAMonthWithNoFlaggedRows() throws {
    let (store, context) = try makeStore()
    insert(flagged: 4, on: date(2026, 9), into: context)
    insert(flagged: 0, unflagged: 2, on: date(2026, 11), into: context)
    try context.save()

    XCTAssertEqual(try store.insights(for: .month(year: 2026, month: 11)).needsReviewCount, 0)
    XCTAssertEqual(try store.needsReviewCountAllTime(), 4)
  }

  // MARK: - The count is the Ledger chip's count

  /// The Ledger's Needs review queue is `LedgerFilterPredicate.matches` with
  /// `needsReviewOnly` and no period. Both read the same rows.
  func testAllTimeCountEqualsTheLedgerQueue() throws {
    let (store, context) = try makeStore()
    insert(flagged: 2, unflagged: 3, on: date(2026, 8), into: context)
    insert(flagged: 4, unflagged: 1, on: date(2026, 9), into: context)
    insert(flagged: 1, unflagged: 5, on: date(2026, 10), into: context)
    try context.save()

    let rows = try context.fetch(FetchDescriptor<NomiCore.Transaction>())
    let ledgerQueue = rows.filter {
      LedgerFilterPredicate.matches($0, filter: TransactionFilter(needsReviewOnly: true), within: nil)
    }

    XCTAssertEqual(ledgerQueue.count, 7)
    XCTAssertEqual(try store.needsReviewCountAllTime(), ledgerQueue.count)
  }

  // MARK: - Not cached

  /// There is no cache to clear. A row written after a read shows on the next
  /// read, without a `WriteCoordinator` call.
  func testTheCountIsReadFromTheStoreOnEachCall() throws {
    let (store, context) = try makeStore()
    XCTAssertEqual(try store.needsReviewCountAllTime(), 0)

    insert(flagged: 1, on: date(2026, 11), into: context)
    try context.save()

    XCTAssertEqual(try store.needsReviewCountAllTime(), 1)
  }

  // MARK: -

  private func makeStore() throws -> (SwiftDataInsightsStore, ModelContext) {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let store = SwiftDataInsightsStore(
      context: stack.context,
      cache: InsightsCache(),
      calendar: calendar,
      now: { [now] in now }
    )
    return (store, stack.context)
  }
}
