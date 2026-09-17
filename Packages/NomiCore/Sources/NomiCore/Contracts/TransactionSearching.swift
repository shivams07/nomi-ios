import Foundation

/// Finding a transaction the ledger window cannot reach (W2-2).
///
/// `LedgerScreen` renders a rolling window — the last N days — and filters it
/// in Swift. That is the right shape for scrolling and the wrong one for
/// searching: a row older than the window cannot be found at all, and the only
/// workaround is widening the window, which is the unbounded whole-ledger read
/// the window exists to prevent. Search is a different query, so it is a
/// different contract.
///
/// Its own file rather than a method on `TransactionStore`, for the reason
/// `CategorySuggesting` and `TransactionEditing` have theirs: `Stores.swift` is
/// a fan-in point that other units own, and this needs none of what is in it.
///
/// `@MainActor` and `AnyObject` to match every other store protocol here — the
/// real implementation holds the container's `mainContext`.
@MainActor
public protocol TransactionSearching: AnyObject {
  /// Rows whose `descriptionText`, `merchantName`, `counterpartyVPA` or `note`
  /// contains `text`, case- and diacritic-insensitively; newest first; at most
  /// `limit`.
  ///
  /// The four fields are the four a user could plausibly be searching by, and
  /// they are not interchangeable: `descriptionText` is the bank's raw
  /// narration, `merchantName` is what the extractor made of it,
  /// `counterpartyVPA` is the UPI handle the row was paid to, and `note` is
  /// what the user typed. A search over only the first two misses every row the
  /// user annotated and every UPI handle they remember better than the
  /// merchant.
  ///
  /// Blank `text` returns `[]` rather than everything. "Contains the empty
  /// string" is true of every row, so the alternative is the whole ledger
  /// truncated to `limit` — a plausible-looking list of unrelated rows,
  /// arriving the instant the user focuses the field and before they type.
  ///
  /// `limit` is a hard cap, not a page size. There is no cursor: this is the
  /// "find that one payment" query, and a user who cannot see their row in the
  /// newest `limit` matches needs a narrower search, not a longer list.
  func search(_ text: String, limit: Int) throws -> [Transaction]
}
