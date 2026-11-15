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

/// A day's two sides, spent and received (S2, artboard Activity). They are display
/// sums of rows already counted, so nothing here is money arithmetic. Transfer legs
/// are out (DEC-05), and so is any row not in INR: the same exclusions as
/// `LedgerDayGroup.totalMinor`, which keeps the period's day totals agreeing with
/// Home's net.
enum LedgerDayTotals {
  static func of<Row: LedgerRow>(_ rows: [Row]) -> (spentMinor: Int, receivedMinor: Int) {
    var spent = 0
    var received = 0
    for row in rows where row.currencyCode == "INR" && !row.isTransfer {
      if row.direction == .credit {
        received += row.amountMinor
      } else {
        spent += row.amountMinor
      }
    }
    return (spent, received)
  }
}

/// The day header's total: spent as "−₹240.00", received as "+₹38,500.00", or
/// both joined by " · " (artboard Activity). A sign is always printed, so the
/// direction is never colour alone (DEC-03 / A-03.4). U+2212 is the minus.
/// `nil` when neither side has money, so a day of transfers shows no total.
enum LedgerDayTotalText {
  static func string(spentMinor: Int, receivedMinor: Int) -> String? {
    var parts: [String] = []
    if spentMinor > 0 {
      parts.append("\u{2212}" + NomiFormatters.amountString(minor: spentMinor))
    }
    if receivedMinor > 0 {
      parts.append("+" + NomiFormatters.amountString(minor: receivedMinor))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

/// Which chip is active. Single-select, not a set: the chips are mutually
/// exclusive views of the same ledger, not toggles to combine. Public so
/// `LedgerScreen`'s `initialChip:` can be set from outside the package.
///
/// `.category` and `.uncategorized` are routed only (Home and Import send them
/// through `ActivityRequest`); the chip row never offers them directly. `.spent`,
/// `.income` and `.transfers` are the row's three kind chips (S2).
public enum LedgerChipSelection: Equatable {
  case all
  case category(UUID)
  case uncategorized
  case needsReview
  case spent
  case income
  case transfers
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
    case .spent, .income, .transfers:
      return rows.filter { kindMatches($0, selection: selection) }
    }
  }

  /// The Spent, Income and Transfers chips (S2). Spent is a debit that is not a
  /// transfer, Income a credit that is not one, and Transfers the transfer legs
  /// in both directions. Every other chip keeps the row, so this is the one rule
  /// the kind chips share. Pure: `LedgerScreen` applies it to the fetched rows.
  static func kindMatches<Row: LedgerRow>(_ row: Row, selection: LedgerChipSelection) -> Bool {
    switch selection {
    case .spent:
      return row.direction == .debit && !row.isTransfer
    case .income:
      return row.direction == .credit && !row.isTransfer
    case .transfers:
      return row.isTransfer
    case .all, .category, .uncategorized, .needsReview:
      return true
    }
  }
}

/// The chip row's state (S2). Pure, so the routed chip and its fall-back are pinned.
enum LedgerChipRow {
  /// The selection the list actually applies. A routed category that no longer
  /// exists has nothing to filter by, so it falls back to All.
  static func effective(_ selection: LedgerChipSelection, categoryNames: [UUID: String]) -> LedgerChipSelection {
    if case .category(let id) = selection, categoryNames[id] == nil {
      return .all
    }
    return selection
  }

  /// The routed chip's title, drawn first in the row with a cross, or nil when the
  /// selection is not routed. Tapping it returns to All.
  static func routedTitle(for selection: LedgerChipSelection, categoryNames: [UUID: String]) -> String? {
    switch selection {
    case .category(let id):
      return categoryNames[id].map { "\($0) ✕" }
    case .uncategorized:
      return "Uncategorized ✕"
    case .all, .needsReview, .spent, .income, .transfers:
      return nil
    }
  }

  /// The To review count's text. Nil at zero, so the tag is hidden rather than
  /// reading "0".
  static func reviewCount(_ count: Int) -> String? {
    count > 0 ? "\(count)" : nil
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
  /// filter is set. Shows "No transactions in <period> yet". The header, search bar
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

  /// "No transactions in November 2026 yet": the period-scoped empty title, from the
  /// States board (S2 step 6). It replaces DEC-04 item 8's "Nothing in <period>".
  static func nothingInPeriodTitle(label: String) -> String {
    "No transactions in \(label) yet"
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

  /// The search field's prompt, from the artboard (S2 step 2).
  static let searchPlaceholder = "Search merchant, note or amount"

  /// The period-empty message, from the States board. It says what goes here and
  /// how it gets there, and claims nothing about other periods.
  static let nothingInPeriodMessage = "They appear here when a bank alert arrives, or when you add one."
}

/// The Activity routing's search prefill (S2 step 3). `.search(text)` from Home or
/// Import puts its text in the search box once. Blank text prefills nothing.
enum LedgerSearchRouting {
  static func prefill(for request: ActivityRequest?) -> String? {
    guard case .search(let text)? = request else { return nil }
    return LedgerSearch.normalized(text)
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
