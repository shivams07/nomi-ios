import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// R12a, I-5. While a month or a financial year is still running, the figure
/// it is compared against is the same number of days from the prior one, and
/// not the whole of it. Pinned to Asia/Kolkata, as the real calendar is.
@MainActor
final class LikeForLikeComparisonTests: XCTestCase {
  private var stacks: [InMemoryStack] = []

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  /// The table in I-5, row for row. Each expected range is half-open and in
  /// IST, so the day boundaries are what the assertion checks.
  func testThePriorWindowIsCutToTheDaysElapsedInTheCurrentPeriod() {
    let cases: [(now: Date, period: InsightPeriod, expected: Range<Date>)] = [
      (date(2026, 11, 3, 15, 0), .month(year: 2026, month: 11),
       date(2026, 10, 1)..<date(2026, 10, 4)),
      (date(2026, 11, 30, 23, 59), .month(year: 2026, month: 11),
       date(2026, 10, 1)..<date(2026, 10, 31)),
      (date(2026, 3, 31, 10, 0), .month(year: 2026, month: 3),
       date(2026, 2, 1)..<date(2026, 3, 1)),
      (date(2026, 12, 5, 10, 0), .month(year: 2026, month: 11),
       date(2026, 10, 1)..<date(2026, 11, 1)),
      (date(2026, 11, 14, 9, 0), .financialYear(startingYear: 2026),
       date(2025, 4, 1)..<date(2025, 11, 15)),
    ]

    for (now, period, expected) in cases {
      XCTAssertEqual(
        InsightsAggregator.priorRange(for: period, calendar: calendar, now: now),
        expected,
        "\(period) at \(now)")
    }
  }

  /// Mid-month, the Home comparison is the first two days of October against
  /// the first two days of November. The 10 October spend is outside it. The
  /// figure comes from the store, so it proves the cut is what the store reads.
  func testHomeComparisonUsesTheCutPrior() throws {
    let context = try makeContext()
    let now = date(2026, 11, 3, 15, 0)

    context.insert(Transaction(date: date(2026, 10, 1), amountMinor: 10_000, directionRaw: Direction.debit.rawValue))
    context.insert(Transaction(date: date(2026, 10, 10), amountMinor: 90_000, directionRaw: Direction.debit.rawValue))
    context.insert(Transaction(date: date(2026, 11, 2), amountMinor: 5_000, directionRaw: Direction.debit.rawValue))
    try context.save()

    let store = SwiftDataInsightsStore(
      context: context, cache: InsightsCache(), calendar: calendar, now: { now })

    let insights = try store.insights(for: .month(year: 2026, month: 11))
    XCTAssertEqual(insights.priorDebitMinor, 10_000, "only 1 October counts")
    XCTAssertEqual(insights.debitMinor, 5_000)
  }

  private func makeContext() throws -> ModelContext {
    let stack = try InMemoryStack(schema: Schema([Transaction.self, NomiCore.Category.self]))
    stacks.append(stack)
    return stack.context
  }
}
