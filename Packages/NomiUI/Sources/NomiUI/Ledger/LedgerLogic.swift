import Foundation
import NomiCore
import SwiftData

/// Anything with the fields a ledger day-group needs to sum and sort — kept
/// separate from `Transaction` so grouping/total math is testable with no
/// container, rather than because none can be built; one can, under XCTest
/// (see `InMemoryModelContainer`'s measured note in NomiCore).
/// `Transaction`'s conformance costs nothing extra; it only reads
/// existing properties, same pattern as `DatedRow` in
/// `Dashboard/RecentTransactionsCard.swift`.
protocol LedgerRow {
  var date: Date { get }
  var amountMinor: Int { get }
  var direction: Direction { get }
  var categoryID: UUID? { get }
  var currencyCode: String { get }
  /// DEC-05. A transfer leg is never spend or income, so it is out of a day
  /// total, the same exclusion `InsightsAggregator` applies to every period
  /// figure. No default: a day total that forgot it would disagree with Home.
  var isTransfer: Bool { get }
}

extension NomiCore.Transaction: LedgerRow {}

/// One calendar day's worth of rows. Callers feed rows already sorted
/// newest-first and `LedgerGrouping.byDay` preserves that order rather than
/// re-sorting, so both the day order and each day's row order come out
/// newest-first.
struct LedgerDayGroup<Row: LedgerRow>: Identifiable {
  let day: Date
  let rows: [Row]

  var id: Date { day }

  /// The sticky header's "day's total" — credits add, debits subtract, so
  /// this is the day's net change, not a sum of magnitudes. INR rows only:
  /// a foreign row's `amountMinor` is in that currency's minor unit, and
  /// adding it to a rupee total would add cents to paise (M-C — same reason
  /// `InsightsAggregator`'s period totals are INR-only). Transfer legs are
  /// left out (DEC-05), so the sum of a period's day totals equals the Home
  /// figure's net for the same period (DEC-04).
  var totalMinor: Int {
    rows.filter { $0.currencyCode == "INR" && !$0.isTransfer }
      .reduce(0) { $0 + ($1.direction == .credit ? $1.amountMinor : -$1.amountMinor) }
  }
}

enum LedgerGrouping {
  /// Buckets by `calendar.startOfDay`, preserving `rows`' own order both
  /// across days (the day of the first row encountered sorts first) and
  /// within a day. Feed it rows already sorted newest-first and the result
  /// reads newest-first top to bottom.
  static func byDay<Row: LedgerRow>(_ rows: [Row], calendar: Calendar = .current) -> [LedgerDayGroup<Row>] {
    var order: [Date] = []
    var buckets: [Date: [Row]] = [:]
    for row in rows {
      let day = calendar.startOfDay(for: row.date)
      if buckets[day] == nil {
        buckets[day] = []
        order.append(day)
      }
      buckets[day]?.append(row)
    }
    return order.map { LedgerDayGroup(day: $0, rows: buckets[$0] ?? []) }
  }
}

/// The day header's total. A day can net negative (more spent than
/// received), so — like `TrackedBalanceText` in `Accounts/AccountsLogic.swift`
/// — this formats a raw signed total rather than a per-transaction
/// debit/credit, and needs its own sign prefix since
/// `NomiFormatters.amountString` always strips it. DEC-03 / A-03.4: the sign
/// is U+2212 for a negative total and "+" for a positive one, and zero carries
/// neither.
enum LedgerDayTotalText {
  static func string(minor: Int) -> String {
    let sign = minor < 0 ? "\u{2212}" : (minor > 0 ? "+" : "")
    return sign + NomiFormatters.amountString(minor: abs(minor))
  }
}

/// Which chip is active. Single-select, not a set — "All", one category,
/// "Uncategorized", or "Needs review" are mutually exclusive views of the
/// same ledger, not independent toggles to combine. Public so `LedgerScreen`'s
/// `initialChip:` can be set from outside the package.
public enum LedgerChipSelection: Equatable {
  case all
  case category(UUID)
  case uncategorized
  case needsReview
}

enum LedgerFiltering {
  static func apply<Row: LedgerRow>(_ rows: [Row], selection: LedgerChipSelection) -> [Row] {
    switch selection {
    case .all:
      return rows
    case .category(let id):
      return rows.filter { $0.categoryID == id }
    case .uncategorized:
      // The same rule Home's uncategorized count uses (DEC-05): transfer legs
      // are ledger rows but never need a category, so they are not listed here.
      return rows.filter {
        TransferRules.countsAsUncategorized(categoryID: $0.categoryID, isTransfer: $0.isTransfer)
      }
    case .needsReview:
      // `LedgerRow` carries no needs-review flag — this pure filtering path
      // is superseded in production by `LedgerFilterPredicate.matches`
      // (`TransactionFilter.needsReviewOnly`, on the real `Transaction`);
      // it stays only for `LedgerFiltering`'s existing tests, so there is
      // nothing meaningful to filter by here.
      return rows
    }
  }
}

/// Which rows the list draws, and so whether a period is in effect (DEC-04,
/// items 6 and 7). `.period` is the selected calendar month or financial year.
/// `.wholeLedger` is the Needs review chip, a work queue, and any search, which
/// reaches the whole ledger. Neither takes a period, so the pill reads "All
/// time", "Show <previous period>" is hidden, and empty copy names no period.
enum LedgerScope: Equatable {
  case period
  case wholeLedger

  static func resolve(selection: LedgerChipSelection, wholeLedgerSearchActive: Bool) -> LedgerScope {
    if selection == .needsReview || wholeLedgerSearchActive {
      return .wholeLedger
    }
    return .period
  }
}

/// What the windowed list reports up to `LedgerScreen`, which owns the chip row
/// (its counts) and the search bar (whether either is shown at all).
/// `hasRows` is the selected period alone, not the search results: a period
/// with no rows is "nothing in this period" while a whole-ledger search runs,
/// and only a store with no rows at all is "no transactions yet".
struct LedgerWindowSummary: Equatable {
  /// The selected period holds a row.
  var hasRows: Bool
  /// The whole table holds a row. Only read when the period is empty, with a
  /// one-row fetch, so the first-run state is never claimed for a user who
  /// has transactions in other periods.
  var storeHasRows: Bool
  /// Every needs-review row in the ledger, not only the period's (DEC-04
  /// item 6): the chip's count is the queue's count.
  var needsReviewCount: Int

  /// Before the list has reported: chips shown, counts zero.
  static let unreported = LedgerWindowSummary(hasRows: true, storeHasRows: true, needsReviewCount: 0)
}

/// Which empty treatment the list shows when it has no rows to draw. `.none`
/// means rows are drawn and no empty state applies. The enum name `none` is
/// fine here because the type is not optional.
enum LedgerEmptyKind: Equatable {
  /// The store holds no transactions at all, and no filter is set: the
  /// first-run state, "No transactions yet" with "Add transaction". The chip
  /// row and search bar are hidden, since there is nothing to search or
  /// filter. The period pill stays (LedgerEmpty artboard).
  case empty
  /// The selected period is empty but the store holds rows elsewhere, and no
  /// filter is set. Shows "Nothing in <period>". The period pill, search bar
  /// and chips stay, and "Show <previous period>" sits below.
  case nothingRecent
  /// A chip or search is active and empties the list. Shows the query and
  /// "Clear filters".
  case noResults
  case none

  static func of(hasRows: Bool, storeHasRows: Bool, isFiltered: Bool) -> LedgerEmptyKind {
    if isFiltered { return .noResults }
    if hasRows { return .none }
    return storeHasRows ? .nothingRecent : .empty
  }
}

/// Copy for the empty and no-results states. The query is shown only when
/// there is one, trimmed the same way the search runs (`LedgerSearch.normalized`).
/// A period is named only when one is in effect (`LedgerScope.period`).
enum LedgerCopy {
  static func noResultsTitle(query: String) -> String {
    guard let text = LedgerSearch.normalized(query) else { return "No matches" }
    return "No matches for “\(text)”"
  }

  /// "Nothing in October 2026": the period-scoped empty title (DEC-04, item 8).
  static func nothingInPeriodTitle(label: String) -> String {
    "Nothing in \(label)"
  }

  /// The no-results message. `periodLabel` is nil when no period is in effect
  /// (Needs review, or a search), and then the period is not named.
  static func noResultsMessage(periodLabel: String?) -> String {
    guard let periodLabel else { return "Nothing matches this search and filter." }
    return "Nothing matches this search and filter in \(periodLabel)."
  }

  /// The line under a failed whole-ledger search. The fallback list is the
  /// period, so the period is named when one is in effect.
  static func searchFailedText(periodLabel: String?) -> String {
    guard let periodLabel else { return "Search didn’t run." }
    return "Search didn’t run. Showing \(periodLabel)."
  }

  /// "Show October 2026", the foot-of-list button (DEC-04, item 7).
  static func showPreviousTitle(label: String) -> String {
    "Show \(label)"
  }

  /// The search box's prompt. "Search all transactions" only when a whole-ledger
  /// search service is wired; otherwise the box only filters the period.
  static func searchPrompt(wholeLedger: Bool) -> String {
    wholeLedger ? "Search all transactions" : "Search"
  }

  /// The period-empty message. The whole-ledger clause appears only when
  /// search can actually reach other periods.
  static func nothingInPeriodMessage(wholeLedger: Bool) -> String {
    wholeLedger
      ? "Choose another period from the menu, or search the whole ledger."
      : "Choose another period from the menu."
  }
}

/// U16: the ledger's `@Query` filter, plus the chip/search matching applied
/// to whatever it fetches.
///
/// Two straight CI failures ruled out folding category and search into the
/// `#Predicate` itself: build 34008249071 hit "the compiler is unable to
/// type-check this expression in reasonable time" on the combined date +
/// category + search boolean tree in one expression; splitting that into
/// named `let` sub-expressions (looked like the compiler's own suggested
/// fix) then failed build 34009202915 with "Predicate body may only contain
/// one expression" — a `#Predicate` closure is exactly one expression,
/// always, no multi-statement rewrite is legal syntax for it. So `make`
/// pushes only the date bound into the `@Query`, and `matches` is a plain
/// Swift function, applied to the fetched rows, that carries the chip and
/// search rules.
///
/// G1 (DEC-04): the period is `make(range:)`, a two-sided bound with the same
/// shape `SwiftDataInsightsStore.ledgerRows(in:)` already ships. `matches`
/// enforces the same range again, so a predicate mistake cannot show a row
/// outside the period. The queues are not bounded: `makeNeedsReview()` is a
/// single comparison, and `matches(within: nil)` applies no date bound.
enum LedgerFilterPredicate {
  /// The selected period's `@Query` (G1). Half-open, like `dateRange(for:)`.
  static func make(range: Range<Date>) -> Predicate<NomiCore.Transaction> {
    let start = range.lowerBound
    let end = range.upperBound
    return #Predicate<NomiCore.Transaction> { $0.date >= start && $0.date < end }
  }

  /// The Needs review queue's `@Query`: every flagged row, no date bound (DEC-04,
  /// item 6). A single comparison, so the fetch is the queue and never the table.
  static func makeNeedsReview() -> Predicate<NomiCore.Transaction> {
    #Predicate<NomiCore.Transaction> { $0.needsReview == true }
  }

  /// `within` is the period when one is in effect and `nil` for the queues and
  /// search. It has no default: every caller says which it is.
  static func matches(
    _ transaction: NomiCore.Transaction,
    filter: TransactionFilter,
    within range: Range<Date>?
  ) -> Bool {
    if let range {
      guard range.contains(transaction.date) else { return false }
    }
    if filter.needsReviewOnly {
      guard transaction.needsReview else { return false }
    }
    if filter.uncategorizedOnly {
      // DEC-05: the rule `LedgerFiltering.apply` and Home's count share. A
      // transfer leg is not listed.
      guard TransferRules.countsAsUncategorized(
        categoryID: transaction.categoryID,
        isTransfer: transaction.isTransfer
      ) else { return false }
    } else if !filter.categoryIDs.isEmpty {
      guard let categoryID = transaction.categoryID, filter.categoryIDs.contains(categoryID) else { return false }
    }
    guard !filter.searchText.isEmpty else { return true }
    return transaction.descriptionText.localizedStandardContains(filter.searchText)
      || (transaction.merchantName ?? "").localizedStandardContains(filter.searchText)
      || (transaction.counterpartyVPA ?? "").localizedStandardContains(filter.searchText)
      || (transaction.note ?? "").localizedStandardContains(filter.searchText)
  }
}
