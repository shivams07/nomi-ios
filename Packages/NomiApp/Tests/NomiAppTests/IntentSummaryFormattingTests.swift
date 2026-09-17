import AppIntents
import Foundation
import NomiCore
import XCTest

@testable import NomiApp

/// W2-7. Everything `SpendingSummaryIntent` decides lives in
/// `IntentSummaryFormatting`, because an `AppIntent` needs the intents runtime
/// and a host app and `swift test` has neither — the same split
/// `IntentDraftMappingTests` works under.
///
/// The calendar is pinned to Asia/Kolkata and `now` is always passed. CI runs
/// UTC and a phone in India does not; a month boundary read off the wrong zone
/// summarises the wrong month for everyone in the last five and a half hours of
/// it, and that is a bug that cannot be seen from one machine.
final class IntentSummaryFormattingTests: XCTestCase {

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

  // MARK: - The done-when

  /// ₹12,345.50 spent in September, read as words a person says.
  func testTheDialogForTwelveThousandThreeHundredFortyFiveFiftyInSeptember() {
    let dialog = IntentSummaryFormatting.dialog(
      spentMinor: 1_234_550,
      period: .month(year: 2026, month: 9),
      categoryName: nil
    )

    XCTAssertEqual(
      dialog,
      "You spent twelve thousand three hundred forty-five rupees and fifty paise in September.")
  }

  /// The same requirement, stated in a way no spell-out rule can drift out
  /// from under: a dialog is read aloud, and a numeral in it is a string the
  /// synthesiser has to guess at. There are no digits anywhere in anything this
  /// produces.
  func testTheDialogContainsNoDigitsAtAll() {
    let cases: [(Int, InsightPeriod, String?)] = [
      (1_234_550, .month(year: 2026, month: 9), nil),
      (1_234_550, .month(year: 2026, month: 9), "Food & Dining"),
      (0, .month(year: 2026, month: 1), nil),
      (1, .financialYear(startingYear: 2026), nil),
      (100, .financialYear(startingYear: 2026), "Groceries"),
      (99_999_999, .trailingMonths(6), nil),
      (50, .allTime, nil),
    ]

    for (minor, period, category) in cases {
      let dialog = IntentSummaryFormatting.dialog(
        spentMinor: minor, period: period, categoryName: category)
      XCTAssertFalse(
        dialog.contains(where: \.isNumber),
        "a numeral reached a spoken dialog: \(dialog)")
    }
  }

  // MARK: - The amount

  func testPaiseAreMentionedOnlyWhenThereAreAny() {
    XCTAssertEqual(
      IntentSummaryFormatting.spokenAmount(minor: 1_234_500),
      "twelve thousand three hundred forty-five rupees")
    XCTAssertEqual(
      IntentSummaryFormatting.spokenAmount(minor: 1_234_550),
      "twelve thousand three hundred forty-five rupees and fifty paise")
  }

  /// "one rupees" is the kind of thing that makes a user stop using a shortcut.
  func testSingularsAreSingular() {
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 100), "one rupee")
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 1), "one paisa")
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 101), "one rupee and one paisa")
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 200), "two rupees")
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 2), "two paise")
  }

  /// Under a rupee, the rupees half is dropped entirely rather than said as
  /// "zero rupees and fifty paise".
  func testAnAmountUnderOneRupeeIsJustPaise() {
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 50), "fifty paise")
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 99), "ninety-nine paise")
  }

  /// Exactly zero is the one case that says "zero rupees" — `spokenAmount` on
  /// its own has to say *something*, and it is the caller's job to have used
  /// the zero sentence instead. `testZeroGetsItsOwnSentence` is that caller.
  func testZeroSpokenOnItsOwnIsZeroRupees() {
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: 0), "zero rupees")
  }

  /// A spend total is a sum of positive amounts and cannot be negative today.
  /// If one ever arrives, the sign is said out loud: a minus that went silent
  /// here would read as a plausible figure with no hint anything was wrong.
  func testANegativeAmountSaysSoRatherThanGoingSilent() {
    XCTAssertEqual(IntentSummaryFormatting.spokenAmount(minor: -150), "minus one rupee and fifty paise")
  }

  // MARK: - The sentence

  func testACategoryIsNamedInTheSentence() {
    XCTAssertEqual(
      IntentSummaryFormatting.dialog(
        spentMinor: 450_000, period: .month(year: 2026, month: 9), categoryName: "Groceries"),
      "You spent four thousand five hundred rupees on Groceries in September.")
  }

  /// Zero gets its own sentence rather than "you spent zero rupees", which is
  /// true, strange to hear, and indistinguishable from the app having failed to
  /// find anything.
  func testZeroGetsItsOwnSentence() {
    XCTAssertEqual(
      IntentSummaryFormatting.dialog(
        spentMinor: 0, period: .month(year: 2026, month: 9), categoryName: nil),
      "You haven't spent anything in September.")
    XCTAssertEqual(
      IntentSummaryFormatting.dialog(
        spentMinor: 0, period: .month(year: 2026, month: 9), categoryName: "Groceries"),
      "You haven't spent anything on Groceries in September.")
  }

  func testTheFinancialYearIsNamedAsAPersonWouldSayIt() {
    XCTAssertEqual(
      IntentSummaryFormatting.dialog(
        spentMinor: 100, period: .financialYear(startingYear: 2026), categoryName: nil),
      "You spent one rupee in this financial year.")
  }

  /// A month is named, not called "this month". The user asked about a period
  /// they already know, so the answer's job is to confirm *which* period it
  /// read — "you spent that much this month" is unfalsifiable by the person
  /// hearing it and "in September" is not.
  func testEveryMonthHasItsOwnName() {
    let names = (1...12).map {
      IntentSummaryFormatting.periodPhrase(for: .month(year: 2026, month: $0))
    }
    XCTAssertEqual(
      names,
      [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
      ])
  }

  // MARK: - Which period the window resolves to

  /// `now` is 12 September 2026 in Asia/Kolkata throughout.
  func testTheThreeWindowsResolveAgainstTheGivenNow() {
    let now = date(2026, 9, 12)

    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(for: .thisMonth, now: now, calendar: calendar),
      .month(year: 2026, month: 9))
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(for: .lastMonth, now: now, calendar: calendar),
      .month(year: 2026, month: 8))
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .thisFinancialYear, now: now, calendar: calendar),
      .financialYear(startingYear: 2026))
  }

  /// "Last month" in January is December of the previous year, not month zero.
  func testLastMonthInJanuaryIsDecemberOfThePreviousYear() {
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .lastMonth, now: date(2026, 1, 3), calendar: calendar),
      .month(year: 2025, month: 12))
  }

  /// The financial year is India's: 1 April to 31 March, the definition
  /// `NomiCore.dateRange(for:)` already encodes. March belongs to the year
  /// before, and that off-by-one is the whole reason this is tested.
  func testTheFinancialYearTurnsOverOnTheFirstOfApril() {
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .thisFinancialYear, now: date(2026, 3, 31), calendar: calendar),
      .financialYear(startingYear: 2025))
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .thisFinancialYear, now: date(2026, 4, 1), calendar: calendar),
      .financialYear(startingYear: 2026))
  }

  /// The boundary CI cannot see for itself. 23:30 on 30 September in Kolkata is
  /// 18:00 on 30 September in UTC — same month, so that instant proves nothing.
  /// 01:00 on 1 October in Kolkata is 19:30 on 30 September UTC, and *that* is
  /// the pair that separates a correct calendar from `.current` on a UTC
  /// runner: the two must land in different months.
  func testTheMonthBoundaryIsReadInTheGivenCalendarNotTheRunners() {
    let lastHourOfSeptember = date(2026, 9, 30, hour: 23)
    let firstHourOfOctober = date(2026, 10, 1, hour: 1)

    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .thisMonth, now: lastHourOfSeptember, calendar: calendar),
      .month(year: 2026, month: 9))
    XCTAssertEqual(
      IntentSummaryFormatting.insightPeriod(
        for: .thisMonth, now: firstHourOfOctober, calendar: calendar),
      .month(year: 2026, month: 10),
      "read in UTC this instant is still September")
  }

  // MARK: - The AppEnum maps onto the pure one

  /// The one mapping between `SpendingSummaryPeriod` — which Siri resolves
  /// against and which `swift test` cannot exercise through an intent — and the
  /// pure `Window` every test above is written in. A case added to one and not
  /// the other is a period the intent offers and the formatter never sees.
  func testEveryAppEnumCaseMapsToItsOwnWindowAndCoversAllOfThem() {
    let mapped = SpendingSummaryPeriod.allCases.map(\.window)

    XCTAssertEqual(
      Set(mapped).count, SpendingSummaryPeriod.allCases.count,
      "two cases map to the same window")
    XCTAssertEqual(
      Set(mapped), Set(IntentSummaryFormatting.Window.allCases),
      "a Window the intent cannot ask for, or a case the formatter never sees")
  }

  /// The raw values are what a shortcut the user already built stores. Pinned,
  /// because reordering the cases must not change what their shortcut means.
  func testTheAppEnumRawValuesAreStable() {
    XCTAssertEqual(
      SpendingSummaryPeriod.allCases.map(\.rawValue),
      ["thisMonth", "lastMonth", "thisFinancialYear"])
  }
}
