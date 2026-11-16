import Foundation
import NomiCore

/// The pure rules behind the Review queue (S4): which rows it lists and in what
/// order, the count Home shows (S1b), the words a row carries, and the three
/// category tiles a row offers. Values in, values out, so the rules run without a
/// store or a view.
public enum ReviewQueueLogic {
  /// The queue, in order. Every flagged row first, newest first, each listed once.
  /// Then the rows of `now`'s calendar month that have no category, are not
  /// transfers, and are not already listed, newest first. A month row from any
  /// other month is dropped here, so the caller may pass a wider read.
  public static func items(
    flagged: [NomiCore.Transaction],
    monthRows: [NomiCore.Transaction],
    now: Date = Date(),
    calendar: Calendar = NomiCalendar.india
  ) -> [NomiCore.Transaction] {
    var listed = Set<UUID>()
    var result: [NomiCore.Transaction] = []
    for row in newestFirst(flagged) where listed.insert(row.id).inserted {
      result.append(row)
    }
    let month = calendar.dateComponents([.year, .month], from: now)
    var candidates: [NomiCore.Transaction] = []
    for row in monthRows where row.categoryID == nil && !row.isTransfer {
      let rowMonth = calendar.dateComponents([.year, .month], from: row.date)
      if rowMonth.year == month.year && rowMonth.month == month.month {
        candidates.append(row)
      }
    }
    for row in newestFirst(candidates) where listed.insert(row.id).inserted {
      result.append(row)
    }
    return result
  }

  /// Home's Review count (S1b). The same list as `items`, so the card and the
  /// queue always agree.
  public static func count(
    flagged: [NomiCore.Transaction],
    monthRows: [NomiCore.Transaction],
    now: Date = Date(),
    calendar: Calendar = NomiCalendar.india
  ) -> Int {
    items(flagged: flagged, monthRows: monthRows, now: now, calendar: calendar).count
  }

  /// The tag on a row. An uncategorised row needs a category first. A flagged row
  /// says why it was flagged (WR-2 wording). An unassigned row says so, a merge says
  /// how many sources it came from, and anything else reads "Needs review".
  public static func reasonText(for row: NomiCore.Transaction) -> String {
    if row.categoryID == nil && !row.isTransfer {
      return String(localized: "Needs a category", bundle: .module)
    }
    if row.needsReview {
      return TransactionDetailLogic.reviewReasonText(row.needsReviewReason)
    }
    if row.accountID == nil {
      return String(localized: "No account assigned", bundle: .module)
    }
    if row.mergedCount > 1 {
      return TransactionDetailLogic.mergedSourcesText(row.mergedCount)
    }
    return String(localized: "Needs review", bundle: .module)
  }

  /// Where the row came from, in the caption. A UPI row says UPI whatever its
  /// source; any other row names its source.
  public static func sourceLabel(for row: NomiCore.Transaction) -> String {
    if row.upiKindRaw != nil { return "UPI" }
    switch row.source {
    case .email: return String(localized: "Bank alert", bundle: .module)
    case .file: return String(localized: "Statement", bundle: .module)
    case .manual: return String(localized: "Added by hand", bundle: .module)
    }
  }

  /// The caption under the amount: "Yesterday, 13 Nov · 1:18 pm · UPI · no account
  /// matched". The day and time come from Detail's caption, so both screens write
  /// a date the same way. The account is the name when there is one.
  public static func caption(
    for row: NomiCore.Transaction,
    accountName: String?,
    now: Date,
    calendar: Calendar
  ) -> String {
    let when = TransactionDetailLogic.caption(
      date: row.date, now: now, calendar: calendar, accountName: nil)
    let trimmed = accountName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let account = trimmed.isEmpty ? String(localized: "no account matched", bundle: .module) : trimmed
    return [when, sourceLabel(for: row), account].joined(separator: " · ")
  }

  /// The category tiles, as ids: the best guess when there is one, then the two most
  /// used categories in `history` that are not the best guess. The uncategorised and
  /// overflow slices never become a tile. "All categories" is not an id; the model
  /// adds it.
  public static func choiceIDs(bestGuess: UUID?, history: [CategorySlice]) -> [UUID] {
    var ids: [UUID] = []
    if let bestGuess { ids.append(bestGuess) }
    let ranked = history.sorted { lhs, rhs in
      if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
      return lhs.id.uuidString < rhs.id.uuidString
    }
    var others: [UUID] = []
    for slice in ranked {
      guard others.count < 2 else { break }
      guard slice.id != bestGuess else { continue }
      guard slice.id != NomiCore.Category.uncategorizedID else { continue }
      guard slice.id != ReportsCategoryFold.otherOverflowID else { continue }
      guard !others.contains(slice.id) else { continue }
      others.append(slice.id)
    }
    return ids + others
  }

  /// True for a label with no space in it. A single word cannot wrap at a word
  /// boundary, so it scales and then truncates instead.
  public static func isSingleWord(_ text: String) -> Bool {
    text.split(whereSeparator: \.isWhitespace).count <= 1
  }

  /// Newest first. Equal dates fall back to the id, so the order never depends on
  /// the order the store returned them in.
  private static func newestFirst(_ rows: [NomiCore.Transaction]) -> [NomiCore.Transaction] {
    rows.sorted { lhs, rhs in
      if lhs.date != rhs.date { return lhs.date > rhs.date }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }
}
