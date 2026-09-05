import Foundation
import NomiCore

/// Pure logic behind `TransactionDetailScreen`, built from plain values rather
/// than `NomiCore.Transaction` (a `@Model` class) — this package's `swift test`
/// runner cannot construct a `ModelContainer` headlessly (see
/// `InMemoryModelContainer`'s note in NomiCore), so anything this suite needs
/// to exercise has to work without one, same reasoning as `TransactionRow`'s
/// pure helpers.
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
}
