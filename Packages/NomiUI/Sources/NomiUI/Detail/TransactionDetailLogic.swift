import Foundation
import NomiCore

/// Pure logic behind `TransactionDetailScreen`, built from plain values rather
/// than `NomiCore.Transaction` (a `@Model` class), so this suite needs no
/// container to exercise it. Not that one cannot be built — it can, under
/// XCTest (see `InMemoryModelContainer`'s measured note in NomiCore) — the
/// values are simply cheaper. Same reasoning as `TransactionRow`'s pure
/// helpers.
public enum TransactionDetailAction: Hashable, Sendable {
  case category, account, edit, source, markReviewed, delete
}

public enum TransactionDetailLogic {
  /// Every row gets the same four base sections and a delete action;
  /// "Mark reviewed" only appears on a row that is actually flagged — there
  /// is nothing to dismiss otherwise.
  public static func availableActions(needsReview: Bool) -> [TransactionDetailAction] {
    var actions: [TransactionDetailAction] = [.category, .account, .edit, .source]
    if needsReview { actions.append(.markReviewed) }
    actions.append(.delete)
    return actions
  }

  /// One line per `SourceRef`, in array order — the Source section lists
  /// every ref a merge accumulated, not just the newest.
  public static func sourceSummary(refs: [SourceRef]) -> [String] {
    refs.map { "\($0.source.rawValue.capitalized) · \($0.externalID)" }
  }

  /// Every reason this screen can see for a row's flags, in a fixed order.
  /// It cannot know *which* pipeline rule set `needsReview` — only that it is
  /// set — so this reports symptoms, not causes. `isTransfer` is the row's
  /// transfer state (DEC-05 T3): "Transfer" is the last flag, and it reads
  /// `isTransfer` only (Amendment 3, U6).
  public static func flagReasons(accountID: UUID?, needsReview: Bool, mergedCount: Int, isTransfer: Bool) -> [String] {
    var reasons: [String] = []
    if accountID == nil { reasons.append("No account assigned") }
    if needsReview { reasons.append("Needs review") }
    if mergedCount > 1 { reasons.append("Merged from \(mergedCount) sources") }
    if isTransfer { reasons.append("Transfer") }
    return reasons
  }

  /// U24: what `saveEdit()` sends to `TransactionEditing.update`'s `note`
  /// parameter. Blank/whitespace-only input clears the note rather than
  /// storing it — `nil` is what `Transaction.note` uses for "no note", and
  /// the header's "shown when present" check reads exactly that.
  public static func noteToSave(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// The one primary control on the sheet (SIMP §4 call 1, DT): Apply when a
  /// suggestion panel is on screen, else Mark reviewed when the row is
  /// flagged, else none. `hasSuggestion` means the panel actually shows
  /// (`SuggestionRow.isShown`), not merely that a suggestion was read — a
  /// primary on a hidden button would have no action to press.
  public enum PrimaryAction: Hashable, Sendable {
    case apply, markReviewed, none
  }

  public static func primaryAction(hasSuggestion: Bool, needsReview: Bool) -> PrimaryAction {
    if hasSuggestion { return .apply }
    if needsReview { return .markReviewed }
    return .none
  }

  /// DEC-03 / A-03: a debit is stored and shown negative so its "−" always
  /// prints; a credit is positive so its "+" prints. Works whether the stored
  /// `amountMinor` is the magnitude or already signed, so the sign follows
  /// `direction` and never the stored value.
  public static func signedMinor(amountMinor: Int, direction: Direction) -> Int {
    let magnitude = abs(amountMinor)
    return direction == .debit ? -magnitude : magnitude
  }

  // MARK: - DEC-05 transfer copy (T3)

  /// The sentence a marked transfer carries on Detail. It says what the mark
  /// does to the totals, so a mark never changes a figure the copy does not state.
  public static let transferSentence =
    "Not counted as spending or income. This moves money between your own accounts."

  /// What a mark did when no other row shares the group: this row alone is excluded.
  public static let noMatchSentence =
    "No matching payment found on another account. Only this transaction is excluded."

  /// The other leg of a transfer, as Detail names it. `narration` is that row's
  /// `descriptionText`; `date` is its own date.
  public struct TransferPartner: Equatable, Sendable {
    public let narration: String
    public let date: Date

    public init(narration: String, date: Date) {
      self.narration = narration
      self.date = date
    }
  }

  /// The transfer action's title. It reads `isTransfer` alone, never the row's
  /// source, so the screen offers the same action for every marked row
  /// (Amendment 3, U6).
  public static func transferButtonTitle(isTransfer: Bool) -> String {
    isTransfer ? "Not a transfer" : "Mark as transfer"
  }

  /// What a mark made on this screen did, read back after the write. It names
  /// the partner the editor marked in the same write, or says that only this
  /// row is excluded. A blank partner narration is named "another transaction",
  /// so the sentence never has an empty gap in it.
  public static func markOutcome(partner: TransferPartner?) -> String {
    guard let partner else { return noMatchSentence }
    return "Also marked: \(narrationText(partner.narration)), \(NomiFormatters.dayMonthYear.string(from: partner.date))"
  }

  /// What an unmark made on this screen did. Unmarking clears every row in the
  /// group, so a named partner counts as spending or income again, and so does
  /// this row. Without a partner only this row changes, and the sentence says so.
  public static func unmarkOutcome(partner: TransferPartner?) -> String {
    guard let partner else { return "Now counted as spending or income again." }
    return
      "Also unmarked: \(narrationText(partner.narration)), \(NomiFormatters.dayMonthYear.string(from: partner.date)). Both now count as spending or income."
  }

  private static func narrationText(_ narration: String) -> String {
    let trimmed = narration.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "another transaction" : trimmed
  }
}

/// M6: the detail screen's "UPI" section prose. Full words, unlike
/// `TransactionRow.upiKindCapsuleText`'s row-width "P2P"/"Merchant" capsule —
/// the two are different presentations of the same raw value, not one
/// reusing the other.
public enum UPIDisplay {
  public static func kindLabel(_ kindRaw: String) -> String? {
    switch kindRaw {
    case "p2p": return "Person"
    case "p2m": return "Merchant"
    default: return nil
    }
  }
}

/// UI refresh (v5) M4: whether the suggestion panel shows, and its two
/// captions. `CategorySuggesting.suggestion(for:)`'s own doc comment already
/// promises `nil` for a `.manual` row or a candidate matching the current
/// category — this mirrors that contract at the UI layer anyway, the same
/// way `NeedsYouCard` mirrors `DashboardWiring.needsYouIsTappable` rather
/// than trusting the read it was handed stayed valid until render.
public enum SuggestionRow {
  public static func isShown(suggestion: CategorySuggestion?, currentCategoryID: UUID?, categorySource: CategorySource) -> Bool {
    guard let suggestion else { return false }
    guard categorySource != .manual else { return false }
    return suggestion.categoryID != currentCategoryID
  }

  /// The panel's third line: "You filed Swiggy as Food & Dining 4 times" or
  /// "Matches your rule for Swiggy". `merchantLabel` is always the row's own
  /// merchant/description label — the screen has no access to a rule's glob
  /// pattern (no `RuleStore` in this unit's init), so the rule caption names
  /// the transaction, not the pattern that matched it.
  public static func reasonText(reason: CategorySuggestion.Reason, merchantLabel: String, categoryName: String) -> String {
    switch reason {
    case .merchantHistory(let matches):
      return "You filed \(merchantLabel) as \(categoryName) \(matches) time\(matches == 1 ? "" : "s")"
    case .rule:
      return "Matches your rule for \(merchantLabel)"
    }
  }
}
