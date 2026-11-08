import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp
@testable import NomiUI

/// G1, DEC-04 item 1 and A-04.4: a Ledger month equals the Home month for the
/// same data. Home is `InsightsAggregator.insights` (the arithmetic
/// `SwiftDataInsightsStore` calls) and, in the store class below, the store
/// itself. The Ledger is the period's range, the rows in it, grouped by day and
/// summed. Both take their range from `dateRange` and their calendar from the
/// test, so they cannot disagree about a boundary.
///
/// Money. Every vector is exact, in paise. The fixture holds the rows the
/// exclusion rules touch: a transfer leg (DEC-05: listed, never counted), a USD
/// row (INR only, adds 0), a needs-review row (counted, since review is a queue
/// and not an exclusion), and rows one second either side of each edge.
///
/// Run under Asia/Kolkata and America/Los_Angeles (A-04.2), so no edge depends
/// on the machine's zone.
///
/// Two classes. `LedgerPeriodParityTests` works on plain values and needs no
/// container. `LedgerPeriodStoreParityTests` builds real `Transaction` rows and
/// runs the store and the `@Query` predicate; it is the stronger check and the
/// one that could not run on the Mac where this was written (see the PR).
final class LedgerPeriodParityTests: XCTestCase {
  static let zones = ["Asia/Kolkata", "America/Los_Angeles"]

  /// One fixture row, described once and turned into both a Home row and a
  /// Ledger row, so the two sides cannot see different data.
  struct Spec {
    let date: Date
    let minor: Int
    var credit = false
    var currency = "INR"
    var flagged = false
    var transfer = false
  }

  /// The Ledger side of a row, for `LedgerGrouping.byDay`. Mirrors what
  /// `Transaction` gives it.
  struct FixtureLedgerRow: NomiUI.LedgerRow {
    let date: Date
    let amountMinor: Int
    let direction: Direction
    let categoryID: UUID?
    let currencyCode: String
    let isTransfer: Bool
  }

  static func calendar(_ identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  static func at(
    _ cal: Calendar, _ year: Int, _ month: Int, _ day: Int,
    hour: Int = 12, minute: Int = 0, second: Int = 0
  ) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return cal.date(from: components)!
  }

  /// Every row in the fixture, in `cal`'s wall clock.
  static func fixture(_ cal: Calendar) -> [Spec] {
    [
      // November 2026, counted: 1,000.00 debit, 38,500.00 credit, 4,000.00 debit
      // (needs review), 2,500.00 debit on the last second of the month.
      Spec(date: at(cal, 2026, 11, 1, hour: 0), minor: 1_000_00),
      Spec(date: at(cal, 2026, 11, 5), minor: 38_500_00, credit: true),
      Spec(date: at(cal, 2026, 11, 12, hour: 9, minute: 30), minor: 4_000_00, flagged: true),
      Spec(date: at(cal, 2026, 11, 30, hour: 23, minute: 59, second: 59), minor: 2_500_00),
      // November 2026, listed but not counted: a 20,000.00 transfer leg (DEC-05)
      // and a 500 USD cents row (INR only, adds 0).
      Spec(date: at(cal, 2026, 11, 10), minor: 20_000_00, transfer: true),
      Spec(date: at(cal, 2026, 11, 10), minor: 500, currency: "USD"),
      // Just outside November, one second either side of each edge.
      Spec(date: at(cal, 2026, 10, 31, hour: 23, minute: 59, second: 59), minor: 7_777_00, credit: true),
      Spec(date: at(cal, 2026, 12, 1, hour: 0), minor: 9_999_00),
      // Inside FY 2026 (1 Apr 2026 to 31 Mar 2027), outside November.
      Spec(date: at(cal, 2026, 4, 1, hour: 0), minor: 1_000_00, credit: true),
      Spec(date: at(cal, 2027, 3, 31, hour: 23, minute: 59, second: 59), minor: 300_00),
    ]
  }

  static func homeRows(_ specs: [Spec]) -> [NomiApp.LedgerRow] {
    specs.map {
      NomiApp.LedgerRow(
        id: UUID(),
        date: $0.date,
        amountMinor: $0.minor,
        directionRaw: $0.credit ? Direction.credit.rawValue : Direction.debit.rawValue,
        categoryID: nil,
        accountID: nil,
        normalizedDescription: "FIXTURE",
        merchantName: nil,
        descriptionText: "fixture",
        needsReview: $0.flagged,
        currencyCode: $0.currency,
        isTransfer: $0.transfer
      )
    }
  }

  static func ledgerRows(_ specs: [Spec]) -> [FixtureLedgerRow] {
    specs.map {
      FixtureLedgerRow(
        date: $0.date,
        amountMinor: $0.minor,
        direction: $0.credit ? .credit : .debit,
        categoryID: nil,
        currencyCode: $0.currency,
        isTransfer: $0.transfer
      )
    }
  }

  // MARK: - Values: the arithmetic Home and the Ledger share

  /// November on both sides. Net 3,100,000 paise is 1,000.00 + 4,000.00 +
  /// 2,500.00 debited against 38,500.00 credited; the transfer and the USD row
  /// are left out of both.
  func testLedgerNovemberEqualsHomeNovemberOverTheSameRows() {
    for zone in Self.zones {
      let cal = Self.calendar(zone)
      let specs = Self.fixture(cal)
      let now = Self.at(cal, 2026, 11, 20)
      let anchor = Self.at(cal, 2026, 11, 15)

      XCTAssertEqual(
        DashboardPeriod.period(basis: .calendarMonth, anchor: anchor, calendar: cal),
        .month(year: 2026, month: 11), zone)
      let range = LedgerPeriod.range(basis: .calendarMonth, anchor: anchor, calendar: cal, now: now)
      XCTAssertEqual(range, dateRange(for: .month(year: 2026, month: 11), calendar: cal, now: now), zone)

      let inPeriod = Self.ledgerRows(specs).filter { range.contains($0.date) }
      XCTAssertEqual(inPeriod.count, 6, "the list shows the transfer and the USD row, zone \(zone)")
      let groups = LedgerGrouping.byDay(inPeriod, calendar: cal)
      let ledgerNet = groups.reduce(0) { $0 + $1.totalMinor }
      XCTAssertEqual(ledgerNet, 3_100_000, zone)

      let home = InsightsAggregator.insights(
        period: .month(year: 2026, month: 11),
        rows: Self.homeRows(specs.filter { range.contains($0.date) }),
        categories: [:],
        priorRows: nil,
        calendar: cal
      )
      XCTAssertEqual(home.debitMinor, 750_000, zone)
      XCTAssertEqual(home.creditMinor, 3_850_000, zone)
      XCTAssertEqual(home.netMinor, 3_100_000, zone)
      XCTAssertEqual(home.transactionCount, 4, zone)
      XCTAssertEqual(ledgerNet, home.netMinor, "a Ledger month equals the Home month, zone \(zone)")
    }
  }

  /// Each November day's total, as the header shows it. Day 10 holds only the
  /// transfer and the USD row, so it totals zero and prints no sign (A-03.4).
  func testNovemberDayTotalsAreTheExactVectors() {
    for zone in Self.zones {
      let cal = Self.calendar(zone)
      let now = Self.at(cal, 2026, 11, 20)
      let range = LedgerPeriod.range(
        basis: .calendarMonth, anchor: Self.at(cal, 2026, 11, 15), calendar: cal, now: now)
      let inPeriod = Self.ledgerRows(Self.fixture(cal)).filter { range.contains($0.date) }

      let groups = LedgerGrouping.byDay(inPeriod, calendar: cal)
      let totalsByDay = Dictionary(
        uniqueKeysWithValues: groups.map { (cal.component(.day, from: $0.day), $0.totalMinor) })
      XCTAssertEqual(totalsByDay, [1: -100_000, 5: 3_850_000, 10: 0, 12: -400_000, 30: -250_000], zone)

      let day10 = groups.first { cal.component(.day, from: $0.day) == 10 }
      XCTAssertEqual(day10?.rows.count, 2, "the transfer and the USD row are listed on their day, zone \(zone)")
    }
  }

  /// FY 2026 is 1 April 2026 to 31 March 2027. Net 2,947,800 paise: October's
  /// 7,777.00 credit, November's 3,100,000, December's 9,999.00 debit, and the
  /// 1 April credit and 31 March debit at either end.
  func testLedgerFinancialYearEqualsHomeFinancialYear() {
    for zone in Self.zones {
      let cal = Self.calendar(zone)
      let specs = Self.fixture(cal)
      let now = Self.at(cal, 2026, 7, 15)
      let range = LedgerPeriod.range(
        basis: .financialYear, anchor: Self.at(cal, 2026, 7, 15), calendar: cal, now: now)
      XCTAssertEqual(range, dateRange(for: .financialYear(startingYear: 2026), calendar: cal, now: now), zone)

      let inPeriod = Self.ledgerRows(specs).filter { range.contains($0.date) }
      XCTAssertEqual(inPeriod.count, 10, zone)
      let ledgerNet = LedgerGrouping.byDay(inPeriod, calendar: cal).reduce(0) { $0 + $1.totalMinor }
      XCTAssertEqual(ledgerNet, 2_947_800, zone)

      let home = InsightsAggregator.insights(
        period: .financialYear(startingYear: 2026),
        rows: Self.homeRows(specs.filter { range.contains($0.date) }),
        categories: [:],
        priorRows: nil,
        calendar: cal
      )
      XCTAssertEqual(home.netMinor, 2_947_800, zone)
      XCTAssertEqual(ledgerNet, home.netMinor, "a Ledger financial year equals the Home one, zone \(zone)")
    }
  }

  /// October and December agree with Home, and each holds only its own
  /// boundary row: 31 October 23:59:59 (credit) and 1 December 00:00:00 (debit).
  func testOctoberAndDecemberAgreeWithHomeAndHoldOnlyTheirOwnBoundaryRow() {
    for zone in Self.zones {
      let cal = Self.calendar(zone)
      let specs = Self.fixture(cal)
      let now = Self.at(cal, 2026, 12, 15)

      for (month, expectedNet) in [(10, 777_700), (12, -999_900)] {
        let range = LedgerPeriod.range(
          basis: .calendarMonth, anchor: Self.at(cal, 2026, month, 15), calendar: cal, now: now)
        let inPeriod = Self.ledgerRows(specs).filter { range.contains($0.date) }
        XCTAssertEqual(inPeriod.count, 1, "month \(month), zone \(zone)")
        let ledgerNet = LedgerGrouping.byDay(inPeriod, calendar: cal).reduce(0) { $0 + $1.totalMinor }
        XCTAssertEqual(ledgerNet, expectedNet, "month \(month), zone \(zone)")

        let home = InsightsAggregator.insights(
          period: .month(year: 2026, month: month),
          rows: Self.homeRows(specs.filter { range.contains($0.date) }),
          categories: [:],
          priorRows: nil,
          calendar: cal
        )
        XCTAssertEqual(ledgerNet, home.netMinor, "month \(month), zone \(zone)")
      }
    }
  }

  /// DEC-05 A-05 item 14 (T3): a transfer pair is out of both sides. Its legs are
  /// unequal on purpose, so a missing exclusion moves the figures (equal legs
  /// would cancel). Hand vector, recomputed in stdlib Python: debit 1,000.00,
  /// credit 3,000.00, net 2,000.00 over two counted rows; day totals 2 Nov
  /// +3,000.00, 10 and 11 Nov zero (transfer legs only), 12 Nov -1,000.00.
  func testTransferPairIsOutOfBothTotalsAtTheExactVectors() {
    for zone in Self.zones {
      let cal = Self.calendar(zone)
      let now = Self.at(cal, 2026, 11, 20)
      let range = LedgerPeriod.range(
        basis: .calendarMonth, anchor: Self.at(cal, 2026, 11, 15), calendar: cal, now: now)
      let specs = [
        Spec(date: Self.at(cal, 2026, 11, 2), minor: 300_000, credit: true),
        Spec(date: Self.at(cal, 2026, 11, 10), minor: 2_000_000, transfer: true),
        Spec(date: Self.at(cal, 2026, 11, 11), minor: 500_000, credit: true, transfer: true),
        Spec(date: Self.at(cal, 2026, 11, 12), minor: 100_000),
      ]

      let inPeriod = Self.ledgerRows(specs).filter { range.contains($0.date) }
      let groups = LedgerGrouping.byDay(inPeriod, calendar: cal)
      let totalsByDay = Dictionary(
        uniqueKeysWithValues: groups.map { (cal.component(.day, from: $0.day), $0.totalMinor) })
      XCTAssertEqual(totalsByDay, [2: 300_000, 10: 0, 11: 0, 12: -100_000], zone)
      let ledgerNet = groups.reduce(0) { $0 + $1.totalMinor }
      XCTAssertEqual(ledgerNet, 200_000, zone)

      let home = InsightsAggregator.insights(
        period: .month(year: 2026, month: 11),
        rows: Self.homeRows(specs),
        categories: [:],
        priorRows: nil,
        calendar: cal
      )
      XCTAssertEqual(home.debitMinor, 100_000, zone)
      XCTAssertEqual(home.creditMinor, 300_000, zone)
      XCTAssertEqual(home.netMinor, 200_000, zone)
      XCTAssertEqual(home.transactionCount, 2, zone)
      XCTAssertEqual(ledgerNet, home.netMinor, "a Ledger month equals Home with a transfer pair present, zone \(zone)")
    }
  }
}

/// The store and the predicate, over real `Transaction` rows. Home here is
/// `SwiftDataInsightsStore`, the path the app takes, and the Ledger side is the
/// period's own `@Query` predicate. These construct `@Model` rows, which trap
/// on the Mac this was written on (the same trap hits the untouched
/// `TransactionSearchTests`), so they are unverified there. Run them on a Mac
/// where `TransactionSearchTests` passes.
@MainActor
final class LedgerPeriodStoreParityTests: XCTestCase {

  private func makeRow(_ spec: LedgerPeriodParityTests.Spec) -> Transaction {
    Transaction(
      date: spec.date,
      descriptionText: "fixture",
      amountMinor: spec.minor,
      currencyCode: spec.currency,
      directionRaw: spec.credit ? Direction.credit.rawValue : Direction.debit.rawValue,
      needsReview: spec.flagged,
      transferGroupID: spec.transfer ? UUID() : nil,
      transferSourceRaw: spec.transfer ? TransferSource.manual.rawValue : nil
    )
  }

  /// The container is held by the test case as well as the context. A container
  /// that is released while its `mainContext` is still in use is the lifetime
  /// trap that kills the process on this Mac (the NomiApp test-helper trap).
  private var containers: [ModelContainer] = []

  private func makeContext() throws -> ModelContext {
    let schema = Schema([Transaction.self, NomiCore.Category.self, NomiCore.Account.self])
    let container = try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    containers.append(container)
    return container.mainContext
  }

  private func insertFixture(into context: ModelContext, _ cal: Calendar) {
    LedgerPeriodParityTests.fixture(cal).map(makeRow).forEach { context.insert($0) }
    try? context.save()
  }

  /// The Ledger side: the period's own predicate, fetched, grouped by day.
  private func ledgerGroups(
    _ context: ModelContext, range: Range<Date>, _ cal: Calendar
  ) throws -> [LedgerDayGroup<Transaction>] {
    let rows = try context.fetch(FetchDescriptor<Transaction>(predicate: LedgerFilterPredicate.make(range: range)))
    return LedgerGrouping.byDay(rows, calendar: cal)
  }

  func testStoreNovemberEqualsHomeNovemberAndThePredicateFetchesTheSixRows() throws {
    for zone in LedgerPeriodParityTests.zones {
      let cal = LedgerPeriodParityTests.calendar(zone)
      let context = try makeContext()
      insertFixture(into: context, cal)
      let now = LedgerPeriodParityTests.at(cal, 2026, 11, 20)
      let range = LedgerPeriod.range(
        basis: .calendarMonth, anchor: LedgerPeriodParityTests.at(cal, 2026, 11, 15), calendar: cal, now: now)

      let groups = try ledgerGroups(context, range: range, cal)
      XCTAssertEqual(groups.reduce(0) { $0 + $1.rows.count }, 6, zone)
      let ledgerNet = groups.reduce(0) { $0 + $1.totalMinor }
      XCTAssertEqual(ledgerNet, 3_100_000, zone)

      let home = try SwiftDataInsightsStore(
        context: context, cache: InsightsCache(), calendar: cal, now: { now }
      ).insights(for: .month(year: 2026, month: 11))
      XCTAssertEqual(home.netMinor, ledgerNet, "a Ledger month equals the Home month, zone \(zone)")
    }
  }

  func testStoreFinancialYearEqualsHomeFinancialYear() throws {
    for zone in LedgerPeriodParityTests.zones {
      let cal = LedgerPeriodParityTests.calendar(zone)
      let context = try makeContext()
      insertFixture(into: context, cal)
      let now = LedgerPeriodParityTests.at(cal, 2026, 7, 15)
      let range = LedgerPeriod.range(
        basis: .financialYear, anchor: now, calendar: cal, now: now)

      let ledgerNet = try ledgerGroups(context, range: range, cal).reduce(0) { $0 + $1.totalMinor }
      XCTAssertEqual(ledgerNet, 2_947_800, zone)

      let home = try SwiftDataInsightsStore(
        context: context, cache: InsightsCache(), calendar: cal, now: { now }
      ).insights(for: .financialYear(startingYear: 2026))
      XCTAssertEqual(ledgerNet, home.netMinor, zone)
    }
  }

  /// The queue's own predicate fetches every flagged row, whatever its date, so
  /// the chip's count and its list are one set. Three flagged rows in three
  /// periods; only one of them is in November.
  func testNeedsReviewPredicateFetchesEveryFlaggedRowRegardlessOfPeriod() throws {
    for zone in LedgerPeriodParityTests.zones {
      let cal = LedgerPeriodParityTests.calendar(zone)
      let context = try makeContext()
      insertFixture(into: context, cal)
      context.insert(makeRow(.init(date: LedgerPeriodParityTests.at(cal, 2025, 1, 15), minor: 1_200_00, flagged: true)))
      context.insert(makeRow(.init(date: LedgerPeriodParityTests.at(cal, 2026, 10, 3), minor: 800_00, flagged: true)))
      try context.save()

      let flagged = try context.fetch(FetchDescriptor<Transaction>(predicate: LedgerFilterPredicate.makeNeedsReview()))
      XCTAssertEqual(flagged.count, 3, zone)

      let november = LedgerPeriod.range(
        basis: .calendarMonth, anchor: LedgerPeriodParityTests.at(cal, 2026, 11, 15), calendar: cal,
        now: LedgerPeriodParityTests.at(cal, 2026, 11, 20))
      let inNovember = flagged.filter {
        LedgerFilterPredicate.matches($0, filter: TransactionFilter(needsReviewOnly: true), within: november)
      }
      XCTAssertEqual(inNovember.count, 1, "only the November flag falls inside the period, zone \(zone)")
    }
  }

  /// DEC-05 A-05 items 1 and 3 (T3), store level. Two accounts, one unequal
  /// transfer pair (a stress vector: `setTransfer` pairs equal amounts only, so
  /// this group is not reachable through the UI). Before the mark both legs
  /// count; after it, both are out of Home and out of the Ledger, and the
  /// account balances are identical before and after. Hand vector, recomputed in
  /// stdlib Python. Paise throughout.
  ///   Unmarked: debit 2,100,000, credit 800,000, net -1,300,000 (4 rows).
  ///   Marked:   debit 100,000, credit 300,000, net 200,000 (2 rows).
  ///   Ledger day totals marked: 2 Nov 300,000; 10 and 11 Nov 0; 12 Nov -100,000.
  ///   Balances (both states): savings 8,300,000; card 400,000; total 8,700,000.
  func testTransferPairIsOutOfBothTotalsAndLeavesBalancesUnchanged() throws {
    try assertPairLeavesTotalsAndBalances(
      incoming: 500_000, unmarkedDebit: 2_100_000, unmarkedCredit: 800_000,
      unmarkedDays: [2: 300_000, 10: -2_000_000, 11: 500_000, 12: -100_000], card: "400000/2")
  }

  /// DEC-05 A-05 item 2 (T3): the pair `setTransfer` can actually create, equal
  /// amounts across two accounts (20,000.00 out of savings, 20,000.00 into the
  /// card). Hand vector, stdlib Python. Before the mark: debit 2,100,000, credit
  /// 2,300,000, net +200,000 (4 rows); day totals 2 Nov 300,000, 10 Nov
  /// -2,000,000, 11 Nov +2,000,000, 12 Nov -100,000. After the mark: debit
  /// 100,000, credit 300,000, net +200,000 (2 rows); the net is unchanged because
  /// the legs are equal. Balances, both states: savings 8,300,000; card 1,900,000.
  func testEqualTransferPairIsOutOfBothTotalsAndLeavesBalancesUnchanged() throws {
    try assertPairLeavesTotalsAndBalances(
      incoming: 2_000_000, unmarkedDebit: 2_100_000, unmarkedCredit: 2_300_000,
      unmarkedDays: [2: 300_000, 10: -2_000_000, 11: 2_000_000, 12: -100_000], card: "1900000/2")
  }

  private func assertPairLeavesTotalsAndBalances(
    incoming incomingMinor: Int, unmarkedDebit: Int, unmarkedCredit: Int, unmarkedDays: [Int: Int], card cardBalance: String
  ) throws {
    for zone in LedgerPeriodParityTests.zones {
      let cal = LedgerPeriodParityTests.calendar(zone)
      let context = try makeContext()
      let now = LedgerPeriodParityTests.at(cal, 2026, 11, 20)
      let range = LedgerPeriod.range(
        basis: .calendarMonth, anchor: LedgerPeriodParityTests.at(cal, 2026, 11, 15), calendar: cal, now: now)

      let savings = NomiCore.Account(displayName: "Savings", kindRaw: "bank", openingBalanceMinor: 10_000_000)
      let card = NomiCore.Account(displayName: "Card", kindRaw: "card", openingBalanceMinor: 0)
      context.insert(savings)
      context.insert(card)
      let salary = Transaction(
        date: LedgerPeriodParityTests.at(cal, 2026, 11, 2), descriptionText: "salary", amountMinor: 300_000,
        directionRaw: Direction.credit.rawValue, accountID: savings.id)
      let outgoing = Transaction(
        date: LedgerPeriodParityTests.at(cal, 2026, 11, 10), descriptionText: "HDFC CREDIT CARD PAYMENT",
        amountMinor: 2_000_000, directionRaw: Direction.debit.rawValue, accountID: savings.id)
      let incoming = Transaction(
        date: LedgerPeriodParityTests.at(cal, 2026, 11, 11), descriptionText: "PAYMENT RECEIVED",
        amountMinor: incomingMinor, directionRaw: Direction.credit.rawValue, accountID: card.id)
      let amazon = Transaction(
        date: LedgerPeriodParityTests.at(cal, 2026, 11, 12), descriptionText: "AMAZON", amountMinor: 100_000,
        directionRaw: Direction.debit.rawValue, accountID: card.id)
      [salary, outgoing, incoming, amazon].forEach { context.insert($0) }
      try context.save()

      func homeNovember() throws -> PeriodInsights {
        try SwiftDataInsightsStore(context: context, cache: InsightsCache(), calendar: cal, now: { now })
          .insights(for: .month(year: 2026, month: 11))
      }
      func balances() throws -> [AccountSummary] {
        try SwiftDataInsightsStore(context: context, cache: InsightsCache(), calendar: cal, now: { now })
          .accountSummaries(includeArchived: false)
      }
      func ledgerDayTotals() throws -> ([Int: Int], Int) {
        let rows = try context.fetch(FetchDescriptor<Transaction>(predicate: LedgerFilterPredicate.make(range: range)))
        let groups = LedgerGrouping.byDay(rows, calendar: cal)
        let byDay = Dictionary(
          uniqueKeysWithValues: groups.map { (cal.component(.day, from: $0.day), $0.totalMinor) })
        return (byDay, groups.reduce(0) { $0 + $1.totalMinor })
      }

      // Before the mark: both legs count.
      let unmarkedHome = try homeNovember()
      XCTAssertEqual(unmarkedHome.debitMinor, unmarkedDebit, zone)
      XCTAssertEqual(unmarkedHome.creditMinor, unmarkedCredit, zone)
      XCTAssertEqual(unmarkedHome.netMinor, unmarkedCredit - unmarkedDebit, zone)
      let unmarkedBalances = try balances()
      let (unmarkedDaysActual, unmarkedNet) = try ledgerDayTotals()
      XCTAssertEqual(unmarkedNet, unmarkedCredit - unmarkedDebit, zone)
      XCTAssertEqual(unmarkedDaysActual, unmarkedDays, zone)

      // The mark: one group on both legs, written the way `setTransfer` writes a manual pair.
      let group = UUID()
      for leg in [outgoing, incoming] {
        leg.transferGroupID = group
        leg.transferSourceRaw = TransferSource.manual.rawValue
      }
      try context.save()

      // After the mark: both legs are out of Home and out of the Ledger.
      let markedHome = try homeNovember()
      XCTAssertEqual(markedHome.debitMinor, 100_000, zone)
      XCTAssertEqual(markedHome.creditMinor, 300_000, zone)
      XCTAssertEqual(markedHome.netMinor, 200_000, zone)
      XCTAssertEqual(markedHome.transactionCount, 2, zone)
      let (markedDays, markedNet) = try ledgerDayTotals()
      XCTAssertEqual(markedDays, [2: 300_000, 10: 0, 11: 0, 12: -100_000], zone)
      XCTAssertEqual(markedNet, markedHome.netMinor, "a Ledger month equals Home after the mark, zone \(zone)")

      // Balances never move with a mark: the same balance and row count per account, before and after.
      func summaryKey(_ summaries: [AccountSummary]) -> [String: String] {
        Dictionary(
          uniqueKeysWithValues: summaries.map {
            ($0.displayName, "\($0.trackedBalanceMinor)/\($0.transactionCount)")
          })
      }
      let markedBalances = try balances()
      XCTAssertEqual(summaryKey(markedBalances), summaryKey(unmarkedBalances), zone)
      XCTAssertEqual(summaryKey(markedBalances), ["Savings": "8300000/2", "Card": cardBalance], zone)
    }
  }
}
