import Foundation
import NomiCore

/// The preview `TransactionSearching` (W2-2).
///
/// Agrees with `SwiftDataTransactionSearch` on every decision that is visible
/// on screen: the same four fields, the same case- and diacritic-insensitive
/// match, newest first, the same `limit` cap, and the same empty answer for a
/// blank query. A preview whose search matched more fields than production's —
/// or fewer — would be a Ledger screen demonstrating results the app cannot
/// produce.
///
/// `localizedStandardContains` is the same call the real predicate makes, so
/// "swiggy" finds "SWIGGY" in both and neither is doing its own case folding.
@MainActor
public final class FakeTransactionSearch: TransactionSearching {
  public var transactions: [Transaction]

  public init(transactions: [Transaction] = PreviewData.transactions) {
    self.transactions = transactions
  }

  public func search(_ text: String, limit: Int) throws -> [Transaction] {
    let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty, limit > 0 else { return [] }

    return
      transactions
      .filter { row in
        row.descriptionText.localizedStandardContains(needle)
          || (row.merchantName?.localizedStandardContains(needle) ?? false)
          || (row.counterpartyVPA?.localizedStandardContains(needle) ?? false)
          || (row.note?.localizedStandardContains(needle) ?? false)
      }
      .sorted { lhs, rhs in
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        // The fake can afford the total tie-break the store cannot: this is a
        // Swift comparison, not a `SortDescriptor`, so `UUID` not being
        // `Comparable` does not stop it. Going further than production here is
        // deliberate and is the one disagreement — a preview list that
        // reshuffles between renders is a preview bug, not a demonstration.
        return lhs.id.uuidString > rhs.id.uuidString
      }
      .prefix(limit)
      .map { $0 }
  }
}
