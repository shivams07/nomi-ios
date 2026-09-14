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
  /// set — so this reports symptoms, not causes.
  public static func flagReasons(accountID: UUID?, needsReview: Bool, mergedCount: Int) -> [String] {
    var reasons: [String] = []
    if accountID == nil { reasons.append("No account assigned") }
    if needsReview { reasons.append("Needs review") }
    if mergedCount > 1 { reasons.append("Merged from \(mergedCount) sources") }
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
