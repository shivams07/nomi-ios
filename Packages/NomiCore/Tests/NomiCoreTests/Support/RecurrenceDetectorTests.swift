import Foundation
import Testing

@testable import NomiCore

/// U17a. The rule is deliberately narrow, so most of these assert what the
/// detector refuses rather than what it finds: the card that renders this is
/// making a claim about money leaving the account next week, and a wrong claim
/// is worse than a missing one.
struct RecurrenceDetectorTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  // MARK: - What it finds

  @Test func threeEvenlySpacedChargesAreASeries() throws {
    let rows = [
      row(daysAfterAnchor: 0),
      row(daysAfterAnchor: 30),
      row(daysAfterAnchor: 60),
    ]

    let series = RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar)

    #expect(series.count == 1)
    let found = try #require(series.first)
    #expect(found.id == "NETFLIX")
    #expect(found.label == "Netflix")
    #expect(found.amountMinor == 49900)
    #expect(found.occurrences == 3)
    #expect(found.lastDate == date(daysAfterAnchor: 60))
    #expect(found.nextExpected == date(daysAfterAnchor: 90), "last charge plus the median gap")
  }

  /// The band is 25...35 days, not "exactly 30". A charge that slips a few days
  /// each month is the normal case, not the exception.
  @Test func gapsInsideTheBandStillCount() {
    let rows = [
      row(daysAfterAnchor: 0),
      row(daysAfterAnchor: 26),
      row(daysAfterAnchor: 61),
    ]

    let series = RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 62), calendar: calendar)

    #expect(series.count == 1)
    // Gaps of 26 and 35 - the median of an even count is the mean of the two,
    // truncated.
    #expect(series.first?.nextExpected == date(daysAfterAnchor: 91))
  }

  /// A price rise inside the tolerance keeps the run, and the reported amount
  /// is the median rather than the newest or the largest.
  @Test func anAmountInsideTheTenPercentBandKeepsTheSeries() {
    let rows = [
      row(daysAfterAnchor: 0, amountMinor: 49900),
      row(daysAfterAnchor: 30, amountMinor: 49900),
      row(daysAfterAnchor: 60, amountMinor: 54000),
    ]

    let series = RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar)

    #expect(series.first?.amountMinor == 49900)
    #expect(series.count == 1)
  }

  /// The dictionary the detector groups into has no stable iteration order, so
  /// the sort is the only reason two runs agree. Two series whose next charges
  /// are a fortnight apart must come back soonest-first every time.
  @Test func seriesComeBackSoonestFirst() {
    let netflix = (0...2).map { row(daysAfterAnchor: $0 * 30) }
    let spotify = (0...2).map {
      row(
        daysAfterAnchor: 14 + $0 * 30,
        amountMinor: 11900,
        description: "SPOTIFY",
        merchant: "Spotify")
    }

    let series = RecurrenceDetector.series(
      in: spotify + netflix,
      now: date(daysAfterAnchor: 75),
      calendar: calendar)

    #expect(series.map(\.id) == ["NETFLIX", "SPOTIFY"])
    #expect(series.map(\.nextExpected) == [date(daysAfterAnchor: 90), date(daysAfterAnchor: 104)])
  }

  // MARK: - What it refuses

  @Test func twoChargesAreNotASeries() {
    let rows = [row(daysAfterAnchor: 0), row(daysAfterAnchor: 30)]

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 31), calendar: calendar).isEmpty)
  }

  @Test func unevenGapsAreNotASeries() {
    let rows = [
      row(daysAfterAnchor: 0),
      row(daysAfterAnchor: 30),
      row(daysAfterAnchor: 75),
    ]

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 76), calendar: calendar).isEmpty)
  }

  @Test func anAmountOutsideTheBandIsNotASeries() {
    let rows = [
      row(daysAfterAnchor: 0, amountMinor: 49900),
      row(daysAfterAnchor: 30, amountMinor: 49900),
      row(daysAfterAnchor: 60, amountMinor: 70000),
    ]

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar).isEmpty)
  }

  /// Salary is the most regular thing in the ledger and the least useful to
  /// warn anyone about.
  @Test func creditsAreIgnored() {
    let rows = (0...2).map {
      row(
        daysAfterAnchor: $0 * 30,
        amountMinor: 8_000_000,
        direction: .credit,
        description: "SALARY",
        merchant: "Acme Payroll")
    }

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar).isEmpty)
  }

  /// The stronger form of the same rule: a credit sitting between two debits
  /// must not enter the run at all. If it were grouped in, its date would break
  /// the gap chain and the real series would disappear with it.
  @Test func aCreditInsideTheWindowDoesNotBreakADebitSeries() {
    let rows = [
      row(daysAfterAnchor: 0),
      row(daysAfterAnchor: 15, direction: .credit),
      row(daysAfterAnchor: 30),
      row(daysAfterAnchor: 60),
    ]

    let series = RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar)

    #expect(series.count == 1)
    #expect(series.first?.occurrences == 3)
  }

  /// A subscription cancelled in March still has three good charges in a
  /// six-month window read in September. `now` is the only thing that stops the
  /// card announcing it as upcoming.
  @Test func aSeriesOverdueByAFullIntervalIsDropped() {
    let rows = [
      row(daysAfterAnchor: 0),
      row(daysAfterAnchor: 30),
      row(daysAfterAnchor: 60),
    ]

    // nextExpected is day 90; the lapse point is 35 days past that.
    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 125), calendar: calendar).count == 1)
    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 126), calendar: calendar).isEmpty)
  }

  /// Rows whose description normalizes to nothing have nothing in common. They
  /// would otherwise all land in the `""` bucket and be reported as one series
  /// under a blank name.
  @Test func rowsWithNoNormalizedDescriptionAreNotGroupedTogether() {
    let rows = [
      row(daysAfterAnchor: 0, description: "", merchant: nil),
      row(daysAfterAnchor: 30, description: "  ", merchant: nil),
      row(daysAfterAnchor: 60, description: "", merchant: nil),
    ]

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar).isEmpty)
  }

  @Test func noRowsIsNotAnError() {
    #expect(RecurrenceDetector.series(in: [], now: date(daysAfterAnchor: 0), calendar: calendar).isEmpty)
  }

  /// Time of day must not decide a gap. Posted at 23:50 and 00:10 thirty days
  /// later is 30 days apart, not 29 and a bit - which `dateComponents` on the
  /// raw instants would have said.
  @Test func gapsAreMeasuredBetweenStartsOfDay() {
    let rows = [
      row(daysAfterAnchor: 0, hour: 23, minute: 50),
      row(daysAfterAnchor: 30, hour: 0, minute: 10),
      row(daysAfterAnchor: 60, hour: 23, minute: 50),
    ]

    #expect(RecurrenceDetector.series(in: rows, now: date(daysAfterAnchor: 61), calendar: calendar).count == 1)
  }

  // MARK: -

  /// 5 January 2026, 10:00 IST. Fixed rather than `Date()` so a run at any hour
  /// of any day produces the same gaps.
  private func date(daysAfterAnchor days: Int, hour: Int = 10, minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 5
    components.hour = hour
    components.minute = minute
    let anchor = calendar.date(from: components)!
    return calendar.date(byAdding: .day, value: days, to: anchor)!
  }

  private func row(
    daysAfterAnchor days: Int,
    amountMinor: Int = 49900,
    direction: Direction = .debit,
    description: String = "NETFLIX",
    merchant: String? = "Netflix",
    hour: Int = 10,
    minute: Int = 0
  ) -> RecurrenceRow {
    RecurrenceRow(
      date: date(daysAfterAnchor: days, hour: hour, minute: minute),
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      normalizedDescription: description,
      merchantName: merchant,
      descriptionText: description
    )
  }
}
