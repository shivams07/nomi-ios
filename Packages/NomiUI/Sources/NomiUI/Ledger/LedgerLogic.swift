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
  /// `InsightsAggregator`'s period totals are INR-only).
  var totalMinor: Int {
    rows.filter { $0.currencyCode == "INR" }
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
/// `NomiFormatters.amountString` always strips it.
enum LedgerDayTotalText {
  static func string(minor: Int) -> String {
    let sign = minor < 0 ? "-" : (minor > 0 ? "+" : "")
    return sign + NomiFormatters.amountString(minor: minor)
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
      return rows.filter { $0.categoryID == nil }
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

/// The magnitude bar's fill fraction — a row's amount relative to the
/// largest amount in whatever set it's drawn against (design: "a data
/// mark," not a fixed scale). A single outsized transaction pins at 1.0
/// rather than the bar overflowing; a zero/empty max floors everyone at 0
/// rather than dividing by zero.
enum LedgerMagnitude {
  static func fraction(amountMinor: Int, maxAmountMinor: Int) -> Double {
    guard maxAmountMinor > 0 else { return 0 }
    let ratio = Double(abs(amountMinor)) / Double(maxAmountMinor)
    return min(max(ratio, 0), 1)
  }
}

/// The 90-day paging window (F1) — the ledger used to load the entire
/// transaction table on every render; `LedgerScreen` builds its `@Query`
/// predicate from `since` instead. `stepsBack` 0 is the screen's first
/// render; each "Show older" tap increments it by one, widening the visible
/// history by another 90 days rather than replacing what's already shown.
enum LedgerWindow {
  static func since(for stepsBack: Int, now: Date, calendar: Calendar = .current) -> Date {
    let days = (stepsBack + 1) * 90
    return calendar.date(byAdding: .day, value: -days, to: now) ?? now
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
/// always, no multi-statement rewrite is legal syntax for it. Rather than
/// guess a third shape blind (no Swift toolchain on this machine to check
/// before pushing), `make` now only pushes the proven-safe `since` bound
/// into the `@Query`; `matches` is a plain Swift function — no expression-
/// count ceiling — that `LedgerTransactionList` applies to the fetched rows,
/// same shape as the `LedgerFiltering.apply` pass this replaced.
enum LedgerFilterPredicate {
  static func make(since: Date) -> Predicate<NomiCore.Transaction> {
    #Predicate<NomiCore.Transaction> { $0.date >= since }
  }

  static func matches(_ transaction: NomiCore.Transaction, filter: TransactionFilter) -> Bool {
    if filter.needsReviewOnly {
      guard transaction.needsReview else { return false }
    }
    if filter.uncategorizedOnly {
      guard transaction.categoryID == nil else { return false }
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
