import Foundation
import NomiCore
import SwiftData

/// The real `TransactionSearching` (W2-2).
///
/// One `FetchDescriptor` with the four clauses OR'd, `fetchLimit` set and
/// sorted by date descending — the design's first choice, and it is what
/// compiled; the four-descriptors-unioned fallback was not needed.
///
/// One descriptor matters for more than tidiness. Four unioned would mean four
/// round trips, a `Set` de-duplication in Swift, and a re-sort of the union —
/// and each descriptor would need its own `fetchLimit` of `limit` to stay
/// bounded, so the worst case is four times the rows crossing the boundary to
/// produce the same answer. SQLite does all of it here.
///
/// **The optional fields are unwrapped at the call, not at the value.** Three of
/// the four columns are `String?`, and the clause is written
/// `($0.merchantName?.localizedStandardContains(text) ?? false)`.
///
/// The other way round — `($0.merchantName ?? "").localizedStandardContains(x)`
/// — compiles, and then throws at `fetch`. CoreData gets handed
/// `TERNARY(merchantName != nil, merchantName, "") CONTAINS[cdl] "x"` and
/// answers `unimplemented SQL generation for predicate … (bad RHS)`: a ternary
/// in *string* position is not something it can compile. Coalescing the
/// `Bool` instead keeps the ternary out of the comparison's operands.
///
/// That distinction is invisible at the type level, which is why every test for
/// this type runs against a real container. `#Predicate` compiles far more than
/// SwiftData can carry into a store query, and the gap is a runtime throw.
///
/// Read-only, so no `WriteCoordinator` and no cache. It is not an aggregate —
/// there is nothing to invalidate — and it runs once per keystroke-debounce on
/// a screen that is already fetching.
@MainActor
public final class SwiftDataTransactionSearch: TransactionSearching {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func search(_ text: String, limit: Int) throws -> [Transaction] {
    let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Both guards are the same guard: a query that would return the whole
    // ledger, and a query that was asked for nothing. Neither should reach
    // SQLite. Trimmed, because a field the user has typed one space into is
    // not a search either.
    guard !needle.isEmpty, limit > 0 else { return [] }

    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> {
        $0.descriptionText.localizedStandardContains(needle)
          || ($0.merchantName?.localizedStandardContains(needle) ?? false)
          || ($0.counterpartyVPA?.localizedStandardContains(needle) ?? false)
          || ($0.note?.localizedStandardContains(needle) ?? false)
      },
      sortBy: [
        SortDescriptor(\Transaction.date, order: .reverse),
        // A tie-break, for the reason every ordering in `InsightsAggregator`
        // has one: `date` alone is not unique — an imported statement gives a
        // whole day the same timestamp — and two rows that compare equal come
        // back in whatever order the store gave them, so a search result
        // reshuffles between renders and reads as rows appearing and
        // disappearing.
        //
        // `createdAt` and not `id`, which would make it total: `UUID` is not
        // `Comparable`, so it cannot be a `SortDescriptor` key at all. Two rows
        // sharing a date *and* a creation instant are still unordered; that is
        // the same residue `TransferDetector`'s "ties by createdAt then id"
        // leaves, and it is as far as a store-side sort can go.
        SortDescriptor(\Transaction.createdAt, order: .reverse),
      ]
    )
    descriptor.fetchLimit = limit
    return try context.fetch(descriptor)
  }
}
