import Foundation
import NomiCore

/// Anything with the fields a ledger day-group needs to sum and sort — kept
/// separate from `Transaction` so grouping/total math is testable without
/// constructing an `@Model` instance (this package's `swift test` runner
/// cannot do that headlessly; see `InMemoryModelContainer`'s note in
/// NomiCore). `Transaction`'s conformance costs nothing extra; it only reads
/// existing properties, same pattern as `DatedRow` in
/// `Dashboard/RecentTransactionsCard.swift`.
protocol LedgerRow {
  var date: Date { get }
  var amountMinor: Int { get }
  var direction: Direction { get }
  var categoryID: UUID? { get }
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
  /// this is the day's net change, not a sum of magnitudes.
  var totalMinor: Int {
    rows.reduce(0) { $0 + ($1.direction == .credit ? $1.amountMinor : -$1.amountMinor) }
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

/// Which chip is active. Single-select, not a set — "All", one category, or
/// "Uncategorized" are mutually exclusive views of the same ledger, not
/// independent toggles to combine.
enum LedgerChipSelection: Equatable {
  case all
  case category(UUID)
  case uncategorized
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
