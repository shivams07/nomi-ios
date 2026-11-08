import Foundation

// clt-harness: include

/// The Ledger search box's query rules (D2).
///
/// `LedgerScreen` sends a non-blank query to `TransactionSearching`, which
/// searches the whole ledger rather than the 90-day window. The contract
/// returns `[]` for blank text, so this is where blank is decided: a blank
/// box shows the normal windowed list, never an empty result.
enum LedgerSearch {
  /// Hard cap on rows returned for one query. The contract has no paging, so
  /// a query matching more than this shows the newest `limit` only.
  static let limit = 200

  /// Quiet period after the last keystroke before the search runs. Each
  /// keystroke cancels the previous task (`.task(id:)`), so only the settled
  /// query reaches the store.
  static let debounceNanoseconds: UInt64 = 250_000_000

  /// The query as the search receives it: trimmed of surrounding whitespace
  /// and newlines, or `nil` when nothing is left to search for.
  static func normalized(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
