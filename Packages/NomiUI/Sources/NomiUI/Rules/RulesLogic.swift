import Foundation
import NomiCore

/// Drag-to-reorder writes priority through `RuleStore.reorder(_:)`, which
/// takes the full ordered id list. Pulled out as a pure function operating on
/// plain `UUID`s — never an `@Model` `Rule` — so it is testable with no
/// container. Not because none can be built; one can, under XCTest (see
/// `InMemoryModelContainer`'s measured note in NomiCore).
enum RulesReorder {
  static func orderedIDs(current: [UUID], from source: IndexSet, to destination: Int) -> [UUID] {
    var ids = current
    ids.move(fromOffsets: source, toOffset: destination)
    return ids
  }
}

/// The rule editor's Save gate: a pattern and a category are both required,
/// and the "Only when" range — if the user set both bounds — has to admit at
/// least one amount. `RuleScope.isValidRange` already answers that (and is
/// `true` for `.any`, an empty scope, and any scope with only one bound set);
/// this just folds it into the one gate the Save button checks (W2-M4).
enum RuleFormGate {
  static func isValid(pattern: String, categoryID: UUID?, scope: RuleScope) -> Bool {
    !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && categoryID != nil
      && scope.isValidRange
  }
}

/// Maps the "Only when" section's min/max amount `TextField`s onto
/// `RuleScope`'s optional bounds, through `EntryAmount`'s parsing — the same
/// rule the entry and budget amount fields already use, so none of the three
/// can drift on what counts as a valid number. Empty or unparseable text is
/// "no bound", not a bound of zero: a zero-magnitude bound is never what
/// "don't care" should mean for an inclusive amount range.
enum RuleScopeAmount {
  static func bound(from text: String) -> Int? {
    let minorUnits = EntryAmount.minorUnits(from: text)
    return minorUnits > 0 ? minorUnits : nil
  }
}

/// The row's "Only when ..." summary line (W2-M4) — `nil` when the scope is
/// `.any`, so an unscoped rule's row renders exactly as it always has.
///
/// Takes an account-name lookup closure rather than `[NomiCore.Account]`
/// directly, the same reason `RuleScope.admits` takes primitives instead of a
/// row type: `Account` is a `@Model` this target's tests cannot construct
/// under `swift test` (SwiftData's headless bundle-name lookup fails first),
/// so a signature that needed one here would make this untestable for no
/// gain — the caller already has the array to close over.
enum RuleScopeSummary {
  static func text(for scope: RuleScope, accountName: (UUID) -> String?) -> String? {
    guard !scope.isAny else { return nil }
    var parts: [String] = []
    if let direction = scope.direction {
      parts.append(direction == .debit ? "Debit" : "Credit")
    }
    if let accountID = scope.accountID {
      parts.append(accountName(accountID) ?? "Unknown account")
    }
    switch (scope.minAmountMinor, scope.maxAmountMinor) {
    case let (.some(minAmount), .some(maxAmount)):
      parts.append("\(NomiFormatters.amountString(minor: minAmount))–\(NomiFormatters.amountString(minor: maxAmount))")
    case let (.some(minAmount), nil):
      parts.append("≥ \(NomiFormatters.amountString(minor: minAmount))")
    case let (nil, .some(maxAmount)):
      parts.append("≤ \(NomiFormatters.amountString(minor: maxAmount))")
    case (nil, nil):
      break
    }
    return parts.joined(separator: " · ")
  }
}

/// Formats `RuleStore.preview(pattern:)`'s live match count.
enum RuleMatchSummary {
  static func text(for count: Int) -> String {
    switch count {
    case 0: return "Matches 0 transactions"
    case 1: return "Matches 1 transaction"
    default: return "Matches \(count) transactions"
    }
  }
}

/// What a rule's row offers, gated on `Rule.isSystem`. A system rule may be
/// turned off but not deleted — deleting it is indistinguishable from one
/// `DefaultRuleSeed` never got to, and the seed puts it straight back (see
/// `Rule.isSystem`'s own note). A user rule offers both.
enum RuleRowAction: Hashable {
  case toggle
  case delete
}

enum RuleRowActions {
  static func offered(isSystem: Bool) -> Set<RuleRowAction> {
    isSystem ? [.toggle] : [.toggle, .delete]
  }
}
