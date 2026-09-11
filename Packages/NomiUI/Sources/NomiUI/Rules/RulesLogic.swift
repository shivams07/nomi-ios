import Foundation

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

/// The rule editor's Save gate: a pattern and a category are both required.
enum RuleFormGate {
  static func isValid(pattern: String, categoryID: UUID?) -> Bool {
    !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && categoryID != nil
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
