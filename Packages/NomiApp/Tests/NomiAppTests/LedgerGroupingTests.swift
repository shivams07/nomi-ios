import NomiCore
import XCTest

@testable import NomiApp

/// The ledger's day sections. Run against `LedgerRow` rather than `Transaction`
/// — the protocol exists so this is possible at all, since `swift test` cannot
/// construct a `@Model` in this CI.
final class LedgerGroupingTests: XCTestCase {

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
    return calendar
  }()

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.timeZone = calendar.timeZone
    return calendar.date(from: components)!
  }

  private func row(_ amountMinor: Int, _ direction: Direction, on date: Date) -> LedgerRow {
    LedgerRow(
      id: UUID(),
      date: date,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      categoryID: nil,
      accountID: nil,
      normalizedDescription: "N",
      merchantName: nil,
      descriptionText: "d",
      needsReview: false
    )
  }

  func testRowsGroupIntoDaysNewestFirst() {
    let rows = [
      row(100, .debit, on: date(2026, 4, 3)),
      row(200, .debit, on: date(2026, 4, 1)),
      row(300, .debit, on: date(2026, 4, 5)),
    ]

    let sections = LedgerGrouping.days(rows, calendar: calendar)

    XCTAssertEqual(sections.map(\.id), [
      calendar.startOfDay(for: date(2026, 4, 5)),
      calendar.startOfDay(for: date(2026, 4, 3)),
      calendar.startOfDay(for: date(2026, 4, 1)),
    ])
  }

  /// Day order must not depend on the caller having sorted. This is the same
  /// input as above in the reverse order, and it must produce the same sections.
  func testDayOrderDoesNotDependOnInputOrder() {
    let dates = [date(2026, 4, 1), date(2026, 4, 3), date(2026, 4, 5)]
    let ascending = dates.map { row(100, .debit, on: $0) }
    let descending = dates.reversed().map { row(100, .debit, on: $0) }

    XCTAssertEqual(
      LedgerGrouping.days(ascending, calendar: calendar).map(\.id),
      LedgerGrouping.days(descending, calendar: calendar).map(\.id)
    )
  }

  /// Times of day collapse into one section — the failure mode is one section
  /// per transaction, which looks like the grouping working until you look at
  /// the headers.
  func testEveryHourOfADayLandsInOneSection() {
    let rows = [
      row(100, .debit, on: date(2026, 4, 1, hour: 0)),
      row(200, .debit, on: date(2026, 4, 1, hour: 13)),
      row(300, .debit, on: date(2026, 4, 1, hour: 23)),
    ]

    let sections = LedgerGrouping.days(rows, calendar: calendar)

    XCTAssertEqual(sections.count, 1)
    XCTAssertEqual(sections.first?.rows.count, 3)
  }

  /// "The day's total" is what was spent. Netting a salary credit against it
  /// would make payday's header read as a day of negative spending.
  func testTheHeaderTotalIsDebitsOnly() {
    let rows = [
      row(1_000, .debit, on: date(2026, 4, 1)),
      row(2_000, .debit, on: date(2026, 4, 1)),
      row(50_000, .credit, on: date(2026, 4, 1)),
    ]

    let sections = LedgerGrouping.days(rows, calendar: calendar)

    XCTAssertEqual(sections.first?.spentMinor, 3_000)
    // The credit is still in the section — it renders its own signed amount.
    XCTAssertEqual(sections.first?.rows.count, 3)
  }

  func testADayOfOnlyCreditsHasAZeroHeaderTotal() {
    let sections = LedgerGrouping.days(
      [row(50_000, .credit, on: date(2026, 4, 1))],
      calendar: calendar
    )
    XCTAssertEqual(sections.first?.spentMinor, 0)
  }

  func testAnEmptyLedgerProducesNoSections() {
    XCTAssertTrue(LedgerGrouping.days([LedgerRow](), calendar: calendar).isEmpty)
  }
}
