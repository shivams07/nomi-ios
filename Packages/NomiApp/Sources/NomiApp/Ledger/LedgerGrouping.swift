import Foundation
import NomiCore

/// Anything the ledger can group. Kept as a protocol so the grouping is
/// testable against `LedgerRow` — a value type — rather than only against
/// `Transaction`, which `swift test` cannot construct in this CI (see
/// `NomiCore/Support/InMemoryModelContainer.swift`). `NomiUI`'s `RecentRows`
/// uses the same device for the same reason.
public protocol LedgerGroupable {
  var date: Date { get }
  var amountMinor: Int { get }
  var directionRaw: String { get }
}

extension NomiCore.Transaction: LedgerGroupable {}
extension LedgerRow: LedgerGroupable {}

/// One day of the ledger: its rows, and the header total.
public struct LedgerDaySection<Row>: Identifiable {
  public let id: Date
  public let rows: [Row]
  /// Debits only.
  ///
  /// "The day's total" in a spend tracker is what was spent, and netting a
  /// salary credit against it would make the header for payday read as a day of
  /// negative spending. Credits are still visible — every row shows its own
  /// signed amount — they are just not summed into this number.
  public let spentMinor: Int

  public init(id: Date, rows: [Row], spentMinor: Int) {
    self.id = id
    self.rows = rows
    self.spentMinor = spentMinor
  }
}

public enum LedgerGrouping {
  /// Newest day first; within a day, the order the rows arrived.
  ///
  /// The **days** are sorted here and the **rows** are not, and the asymmetry is
  /// deliberate. `SwiftDataInsightsStore` already sorts descending by date via a
  /// `SortDescriptor`, so SQLite does the expensive half and re-sorting
  /// thousands of rows on every render would be a second opinion about it. The
  /// day keys are at most a few hundred and sorting them costs nothing — and
  /// without it this function would silently depend on its caller having sorted,
  /// which is the kind of contract that holds until someone adds a second
  /// caller.
  public static func days<Row: LedgerGroupable>(
    _ rows: [Row],
    calendar: Calendar = .current
  ) -> [LedgerDaySection<Row>] {
    var grouped: [Date: [Row]] = [:]

    for row in rows {
      grouped[calendar.startOfDay(for: row.date), default: []].append(row)
    }

    return grouped.keys.sorted(by: >).map { day in
      let dayRows = grouped[day] ?? []
      return LedgerDaySection(
        id: day,
        rows: dayRows,
        spentMinor: dayRows
          .filter { $0.directionRaw == Direction.debit.rawValue }
          .reduce(0) { $0 + $1.amountMinor }
      )
    }
  }
}
