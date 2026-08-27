import Foundation

/// Drag-to-reorder writes priority through `RuleStore.reorder(_:)`, which
/// takes the full ordered id list. Pulled out as a pure function operating on
/// plain `UUID`s — never an `@Model` `Rule` — so it is testable without one
/// (this package's `swift test` runner cannot construct `@Model` instances
/// headlessly; see `InMemoryModelContainer`'s note in NomiCore).
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
