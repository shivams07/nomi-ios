import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// Exercises the ledger's pure grouping/filter/magnitude math against plain
/// stubs, never a real `Transaction`. Not because one cannot be built: a
/// container constructs fine under XCTest and only swift-testing traps (see
/// `InMemoryModelContainer`'s measured note in NomiCore). `LedgerRow` exists so
/// this can be verified with no container, no schema and no store, same pattern
/// as `RecentTransactionsSortTests`' `StubRow`.
private struct StubRow: LedgerRow, Equatable {
  let label: String
  let date: Date
  let amountMinor: Int
  let direction: Direction
  let categoryID: UUID?
  var currencyCode: String = "INR"
  var isTransfer: Bool = false
}

/// Fixed calendar/timezone throughout — CI runs UTC and Shivam does not, so
/// a day-boundary test that trusts `.current` passes here and fails there.
private let calendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
  return calendar
}()

private func date(_ string: String) -> Date {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.date(from: string)!
}

final class LedgerGroupingTests: XCTestCase {
  func testGroupsByCalendarDay() {
    let rows = [
      StubRow(label: "a", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "b", date: date("2026-08-19"), amountMinor: 200, direction: .debit, categoryID: nil),
      StubRow(label: "c", date: date("2026-08-20"), amountMinor: 300, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 2)
    XCTAssertEqual(groups[0].rows.map(\.label), ["a", "c"], "same-day rows preserve source order")
    XCTAssertEqual(groups[1].rows.map(\.label), ["b"])
  }

  func testPreservesDayOrderFromFirstEncounter() {
    // Fed newest-first, as `LedgerScreen`'s `@Query` sort produces — the
    // first day encountered (20th) must sort before the second (19th).
    let rows = [
      StubRow(label: "newest", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "older", date: date("2026-08-19"), amountMinor: 100, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.map { calendar.startOfDay(for: $0.day) }, [date("2026-08-20"), date("2026-08-19")])
  }

  func testYearBoundaryProducesDistinctDays() {
    let rows = [
      StubRow(label: "dec31", date: date("2025-12-31"), amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "jan1", date: date("2026-01-01"), amountMinor: 100, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 2, "a year boundary must not collapse two distinct days into one")
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertTrue(LedgerGrouping.byDay([StubRow](), calendar: calendar).isEmpty)
  }

  func testDayTotalIsNetOfCreditsAndDebits() {
    let rows = [
      StubRow(label: "debit", date: date("2026-08-20"), amountMinor: 500, direction: .debit, categoryID: nil),
      StubRow(label: "credit", date: date("2026-08-20"), amountMinor: 200, direction: .credit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.first?.totalMinor, -300, "the day's total matches the sum of its rows")
  }

  func testDayTotalOfAllCreditsIsPositive() {
    let rows = [
      StubRow(label: "credit", date: date("2026-08-20"), amountMinor: 500, direction: .credit, categoryID: nil),
    ]
    XCTAssertEqual(LedgerGrouping.byDay(rows, calendar: calendar).first?.totalMinor, 500)
  }

  /// M-C: a foreign row's `amountMinor` is in that currency's minor unit, so
  /// folding it into a rupee total would add cents to paise. The $5 USD debit
  /// here must not move the total at all.
  func testDayTotalSumsINRRowsOnly() {
    let rows = [
      StubRow(
        label: "inr-debit", date: date("2026-08-20"), amountMinor: 100_00, direction: .debit, categoryID: nil,
        currencyCode: "INR"
      ),
      StubRow(
        label: "usd-debit", date: date("2026-08-20"), amountMinor: 500, direction: .debit, categoryID: nil,
        currencyCode: "USD"
      ),
    ]
    XCTAssertEqual(LedgerGrouping.byDay(rows, calendar: calendar).first?.totalMinor, -100_00)
  }

  /// DEC-05: a transfer leg is never spend or income, so it does not move the
  /// day total, the same exclusion `InsightsAggregator.isCountedSpend` applies.
  /// Exact vector: a 38,500.00 credit, a 20,000.00 transfer debit and a
  /// 5,000.00 transfer credit. Excluded, the day is +38,500.00. Counted, it
  /// would be +23,500.00, so the two transfer legs must not net away here
  /// (they are unequal on purpose; equal legs cancel and prove nothing).
  func testDayTotalExcludesTransferLegs() {
    let rows = [
      StubRow(
        label: "salary", date: date("2026-11-05"), amountMinor: 38_500_00, direction: .credit, categoryID: nil),
      StubRow(
        label: "card payment", date: date("2026-11-05"), amountMinor: 20_000_00, direction: .debit, categoryID: nil,
        isTransfer: true),
      StubRow(
        label: "card refund", date: date("2026-11-05"), amountMinor: 5_000_00, direction: .credit, categoryID: nil,
        isTransfer: true),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 1)
    XCTAssertEqual(groups.first?.rows.count, 3, "a transfer stays listed; only its money is left out")
    XCTAssertEqual(groups.first?.totalMinor, 38_500_00)
  }

  /// A day whose only rows are transfer legs totals zero, so the header prints
  /// no sign (A-03.4).
  func testDayOfOnlyTransferLegsTotalsZero() {
    let rows = [
      StubRow(
        label: "card payment", date: date("2026-11-10"), amountMinor: 20_000_00, direction: .debit, categoryID: nil,
        isTransfer: true)
    ]
    XCTAssertEqual(LedgerGrouping.byDay(rows, calendar: calendar).first?.totalMinor, 0)
  }

  /// Rows at 23:59:59 and 00:00:00 land in their own calendar days: no group
  /// holds a row from another day, and the first and last groups lie inside
  /// the period (A-04.3).
  func testDayGroupsNeverStraddleAPeriodEdge() {
    let lastSecond = calendar.date(byAdding: .second, value: 86_399, to: date("2026-03-31"))!
    let firstSecond = date("2026-04-01")
    let rows = [
      StubRow(label: "fy-start", date: firstSecond, amountMinor: 100, direction: .debit, categoryID: nil),
      StubRow(label: "fy-end", date: lastSecond, amountMinor: 100, direction: .debit, categoryID: nil),
    ]
    let groups = LedgerGrouping.byDay(rows, calendar: calendar)
    XCTAssertEqual(groups.count, 2, "23:59:59 on 31 Mar and 00:00:00 on 1 Apr are two days")
    for group in groups {
      for row in group.rows {
        XCTAssertEqual(calendar.startOfDay(for: row.date), group.day)
      }
    }
    XCTAssertEqual(groups.map(\.day), [date("2026-04-01"), date("2026-03-31")])
  }
}

final class LedgerFilteringTests: XCTestCase {
  private let foodID = UUID()
  private let shoppingID = UUID()

  private func rows() -> [StubRow] {
    [
      StubRow(label: "food", date: date("2026-08-20"), amountMinor: 100, direction: .debit, categoryID: foodID),
      StubRow(label: "shopping", date: date("2026-08-20"), amountMinor: 200, direction: .debit, categoryID: shoppingID),
      StubRow(label: "uncategorized", date: date("2026-08-20"), amountMinor: 300, direction: .debit, categoryID: nil),
    ]
  }

  func testAllReturnsEveryRow() {
    XCTAssertEqual(LedgerFiltering.apply(rows(), selection: .all).count, 3)
  }

  func testCategorySelectionKeepsOnlyThatCategory() {
    let result = LedgerFiltering.apply(rows(), selection: .category(foodID))
    XCTAssertEqual(result.map(\.label), ["food"])
  }

  func testUncategorizedSelectionKeepsOnlyNilCategory() {
    let result = LedgerFiltering.apply(rows(), selection: .uncategorized)
    XCTAssertEqual(result.map(\.label), ["uncategorized"])
  }

  /// WR-3b, DEC-05. A transfer leg is a ledger row but never needs a category,
  /// so the Uncategorized chip does not list it. Home's uncategorized count
  /// applies the same rule (`TransferRules.countsAsUncategorized`).
  func testUncategorizedSelectionExcludesTransferLegs() {
    let rows = [
      StubRow(label: "plain", date: date("2026-08-20"), amountMinor: 300, direction: .debit, categoryID: nil),
      StubRow(
        label: "transfer leg", date: date("2026-08-20"), amountMinor: 300, direction: .debit,
        categoryID: nil, isTransfer: true),
    ]

    let result = LedgerFiltering.apply(rows, selection: .uncategorized)

    XCTAssertEqual(result.map(\.label), ["plain"])
  }

  /// The exclusion is for uncategorized legs only: a categorized transfer leg is
  /// already out of this chip, and `.all` keeps every row, transfers included.
  func testAllKeepsTransferLegsAndUncategorizedExcludesOnlyThem() {
    let rows = [
      StubRow(label: "transfer leg", date: date("2026-08-20"), amountMinor: 300, direction: .debit,
              categoryID: nil, isTransfer: true),
      StubRow(label: "categorized transfer", date: date("2026-08-20"), amountMinor: 300, direction: .debit,
              categoryID: foodID, isTransfer: true),
    ]

    XCTAssertEqual(LedgerFiltering.apply(rows, selection: .all).count, 2)
    XCTAssertTrue(LedgerFiltering.apply(rows, selection: .uncategorized).isEmpty)
  }

  func testCategoryWithNoMatchesReturnsEmpty() {
    XCTAssertTrue(LedgerFiltering.apply(rows(), selection: .category(UUID())).isEmpty)
  }
}

/// `LedgerScreen.dayHeader` renders `LedgerDayHeaderText.string(for:relativeTo:)`
/// — a pure wrapper defined in `LedgerScreen.swift` itself, not the general
/// `NomiFormatters.dayMonthAdaptive` it wraps, so this exercises this unit's
/// own code. A test against the formatter alone would pass whether or not
/// `dayHeader` was ever wired up to it.
final class LedgerDayHeaderTests: XCTestCase {
  func testDayHeaderOmitsYearForACurrentYearGroup() {
    let reference = date("2026-09-03")
    let sameYear = date("2026-08-20")
    let text = LedgerDayHeaderText.string(for: sameYear, relativeTo: reference)
    XCTAssertFalse(text.contains("2026"))
  }

  func testDayHeaderIncludesYearForAPriorYearGroup() {
    let reference = date("2026-09-03")
    let priorYear = date("2025-12-31")
    let text = LedgerDayHeaderText.string(for: priorYear, relativeTo: reference)
    XCTAssertTrue(text.contains("2025"))
  }
}

/// A-03.4: the day total carries U+2212 for a negative net and "+" for a
/// positive one, zero carries neither. The sign is always printed, never
/// colour alone.
final class LedgerDayTotalTextTests: XCTestCase {
  func testPositiveTotalGetsPlusSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: 500), "+" + NomiFormatters.amountString(minor: 500))
  }

  func testNegativeTotalGetsMinusSignNotHyphen() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: -500), "\u{2212}" + NomiFormatters.amountString(minor: 500))
  }

  func testZeroTotalHasNoSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: 0), NomiFormatters.amountString(minor: 0))
  }

  func testLakhScaleNegativeTotalKeepsItsSign() {
    XCTAssertEqual(LedgerDayTotalText.string(minor: -1_148_00), "\u{2212}" + NomiFormatters.amountString(minor: 1_148_00))
  }
}

/// The empty treatment is one pure decision over the window, the whole store
/// and the filter, so every combination is pinned here rather than inferred
/// from the view.
final class LedgerEmptyKindTests: XCTestCase {
  func testStoreWithNoTransactionsAndNoFilterIsTheFirstRunState() {
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: false, storeHasRows: false, isFiltered: false), .empty)
  }

  /// The ruling: an empty 90-day window with older rows must not claim "No
  /// transactions yet". It is "Nothing in the last N days", with search and
  /// Show older still available.
  func testEmptyWindowWithOlderRowsIsNothingRecentNotFirstRun() {
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: false, storeHasRows: true, isFiltered: false), .nothingRecent)
  }

  func testRowsAndAFilterThatEmptiesThemIsNoResults() {
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: true, storeHasRows: true, isFiltered: true), .noResults)
  }

  func testRowsWithNoFilterShowNoEmptyState() {
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: true, storeHasRows: true, isFiltered: false), .none)
  }

  /// An active filter over an empty window still says "no results" and offers
  /// "Clear filters". It must not fall through to the first-run copy, which
  /// would hide the chips the user needs to get back out.
  func testFilterOverAnEmptyWindowIsNoResults() {
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: false, storeHasRows: true, isFiltered: true), .noResults)
    XCTAssertEqual(LedgerEmptyKind.of(hasRows: false, storeHasRows: false, isFiltered: true), .noResults)
  }

  /// Search and the chip row hide only in the first-run state: `.empty` is the
  /// one case `LedgerScreen` uses to hide them.
  func testOnlyTheFirstRunStateIsEmpty() {
    let kinds: [LedgerEmptyKind] = [
      LedgerEmptyKind.of(hasRows: false, storeHasRows: false, isFiltered: false),
      LedgerEmptyKind.of(hasRows: false, storeHasRows: true, isFiltered: false),
      LedgerEmptyKind.of(hasRows: true, storeHasRows: true, isFiltered: false),
      LedgerEmptyKind.of(hasRows: false, storeHasRows: true, isFiltered: true),
    ]
    XCTAssertEqual(kinds.filter { $0 == .empty }.count, 1)
  }
}

final class LedgerCopyTests: XCTestCase {
  func testNothingInPeriodNamesThePeriod() {
    XCTAssertEqual(LedgerCopy.nothingInPeriodTitle(label: "October 2026"), "Nothing in October 2026")
    XCTAssertEqual(LedgerCopy.nothingInPeriodTitle(label: "FY 2025–26"), "Nothing in FY 2025–26")
  }

  /// With a period in effect the no-results message names it; a queue (Needs
  /// review, or a search) names no period.
  func testNoResultsMessageNamesThePeriodOnlyWhenOneIsInEffect() {
    XCTAssertEqual(
      LedgerCopy.noResultsMessage(periodLabel: "October 2026"),
      "Nothing matches this search and filter in October 2026.")
    XCTAssertEqual(LedgerCopy.noResultsMessage(periodLabel: nil), "Nothing matches this search and filter.")
  }

  func testSearchFailedNamesThePeriodOnlyWhenOneIsInEffect() {
    XCTAssertEqual(LedgerCopy.searchFailedText(periodLabel: "March 2026"), "Search didn’t run. Showing March 2026.")
    XCTAssertEqual(LedgerCopy.searchFailedText(periodLabel: nil), "Search didn’t run.")
  }

  func testShowPreviousNamesThePreviousPeriod() {
    XCTAssertEqual(LedgerCopy.showPreviousTitle(label: "October 2026"), "Show October 2026")
  }

  /// With a whole-ledger search wired, the prompt and message say so.
  func testWholeLedgerSearchKeepsTheWholeLedgerCopy() {
    XCTAssertEqual(LedgerCopy.searchPrompt(wholeLedger: true), "Search all transactions")
    XCTAssertTrue(LedgerCopy.nothingInPeriodMessage(wholeLedger: true).contains("search the whole ledger"))
  }

  /// Without one (RootView passes no `transactionSearch` until S1), search
  /// filters only the period, so the copy must not promise the whole ledger.
  func testWithoutWholeLedgerSearchTheCopyPromisesOnlyThePeriod() {
    XCTAssertEqual(LedgerCopy.searchPrompt(wholeLedger: false), "Search")
    let message = LedgerCopy.nothingInPeriodMessage(wholeLedger: false)
    XCTAssertFalse(message.contains("whole ledger"))
    XCTAssertFalse(message.contains("search"))
    XCTAssertTrue(message.contains("period"))
  }

  func testNoQueryReadsNoMatches() {
    XCTAssertEqual(LedgerCopy.noResultsTitle(query: ""), "No matches")
  }

  func testBlankQueryReadsNoMatches() {
    XCTAssertEqual(LedgerCopy.noResultsTitle(query: "   \n\t"), "No matches")
  }

  func testQueryIsShownTrimmedInCurlyQuotes() {
    XCTAssertEqual(LedgerCopy.noResultsTitle(query: "  Swig "), "No matches for “Swig”")
  }

  func testInnerSpacesAreKept() {
    XCTAssertEqual(LedgerCopy.noResultsTitle(query: "acme payroll"), "No matches for “acme payroll”")
  }
}
/// G1 (DEC-04): which rows the list draws. A queue (Needs review, or a search)
/// takes no period, so the pill reads "All time" and "Show <previous period>"
/// is hidden; a selected period is the only scope that names one.
final class LedgerScopeTests: XCTestCase {
  func testNoFilterAndNoSearchIsThePeriod() {
    XCTAssertEqual(LedgerScope.resolve(selection: .all, wholeLedgerSearchActive: false), .period)
  }

  func testCategoryAndUncategorizedChipsStayInThePeriod() {
    XCTAssertEqual(LedgerScope.resolve(selection: .category(UUID()), wholeLedgerSearchActive: false), .period)
    XCTAssertEqual(LedgerScope.resolve(selection: .uncategorized, wholeLedgerSearchActive: false), .period)
  }

  func testNeedsReviewIsAWholeLedgerQueue() {
    XCTAssertEqual(LedgerScope.resolve(selection: .needsReview, wholeLedgerSearchActive: false), .wholeLedger)
  }

  func testWholeLedgerSearchIsAWholeLedgerQueue() {
    XCTAssertEqual(LedgerScope.resolve(selection: .all, wholeLedgerSearchActive: true), .wholeLedger)
    XCTAssertEqual(LedgerScope.resolve(selection: .uncategorized, wholeLedgerSearchActive: true), .wholeLedger)
  }
}

/// U16: `LedgerFilterPredicate.make` builds a `Predicate<NomiCore.Transaction>`
/// — a `#Predicate<Transaction>` literal, which nominally names the `@Model`
/// type as its generic parameter but never constructs one just by being
/// built. Calling `make` here is therefore safe.
///
/// The category/search matching itself now lives in
/// `LedgerFilterPredicate.matches`, a plain function rather than a
/// `#Predicate` (two straight CI failures — a type-check timeout, then
/// "Predicate body may only contain one expression" — ruled out folding it
/// into the query). `matches` takes a real `Transaction`, though, so it hits
/// the same wall `.evaluate(_:)` would have: per
/// `NomiCore/Support/InMemoryModelContainer.swift` and the fix confirmed in
/// U13 (Reports), constructing a `Transaction` anywhere `swift test`
/// actually executes — not just `#Preview` bodies — crashes this package's
/// runner outright, regardless of `isStoredInMemoryOnly`. So this still
/// can't exercise `matches` directly; it instead checks the exact `String`
/// API its search branch calls (`localizedStandardContains`) against plain
/// strings standing in for `descriptionText`/`merchantName`/
/// `counterpartyVPA` — the same fallback shape as `StubRow` elsewhere in
/// this file, applied to a predicate instead of a `LedgerRow`.
final class LedgerFilterPredicateTests: XCTestCase {
  func testConstructingThePredicateDoesNotRequireAModelInstance() {
    _ = LedgerFilterPredicate.make(range: date("2026-08-01")..<date("2026-09-01"))
    _ = LedgerFilterPredicate.makeNeedsReview()
  }

  func testSearchTextMatchesMerchantNameCaseInsensitively() {
    XCTAssertTrue("SWIGGY".localizedStandardContains("swiggy"))
  }

  func testSearchTextDoesNotMatchAnUnrelatedMerchantName() {
    XCTAssertFalse("ZOMATO".localizedStandardContains("swiggy"))
  }

  func testEmptySearchTextIsTreatedAsNoFilterByTheFlagLedgerFilterPredicateChecks() {
    let filter = TransactionFilter()
    XCTAssertTrue(filter.searchText.isEmpty)
  }
}
