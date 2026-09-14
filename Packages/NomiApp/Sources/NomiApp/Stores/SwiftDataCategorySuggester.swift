import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The real `CategorySuggesting` (UI refresh P3).
///
/// Read-only and uncached, on purpose. It runs once per sheet open over one
/// merchant's rows. A cache would need a key per transaction and an
/// invalidation story for an answer nobody re-reads, and the sheet re-asks
/// right after Apply expecting the new truth.
///
/// The rules half goes through `RuleSnapshot($0)` (the bridge in
/// `TransactionSnapshotBridge.swift`) and `RuleEngine`, exactly as
/// `SwiftDataRuleStore` and `SwiftDataTransactionStore` do: the same
/// precedence, the same uppercased glob. So a rule suggested here is the rule
/// ingest would have applied, not a second reading of it.
///
/// A candidate is not checked against the `Category` rows. Deleting a category
/// clears it from every row and deletes its rules (`SwiftDataCategoryStore`),
/// so a dangling id can only arrive mid-sync from another device.
@MainActor
public final class SwiftDataCategorySuggester: CategorySuggesting {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func suggestion(for transactionID: UUID) throws -> CategorySuggestion? {
    guard let row = try row(id: transactionID) else { return nil }
    // The user decided, and that includes deciding "no category":
    // `setCategory(_:to: nil)` stamps `.manual` too.
    guard row.categorySourceRaw != CategorySource.manual.rawValue else { return nil }

    // History first. When it has an answer the rules are not consulted at all,
    // not even when that answer is the row's current category: falling through
    // then would offer a glob's opinion against the user's own filing of the
    // same merchant.
    guard let candidate = try fromHistory(row) ?? fromRules(row) else { return nil }
    return candidate.categoryID == row.categoryID ? nil : candidate
  }

  // MARK: -

  /// Other rows sharing `normalizedDescription` that carry a category, counted
  /// per category. Most rows wins; a tie goes to the smaller `uuidString`, the
  /// same arbitrary-but-stable last resort `RuleEngine.precedenceOrdered` uses,
  /// so two sheet opens and two devices agree.
  ///
  /// A blank description is not a merchant. Every row with no description
  /// normalises to the same empty string, so its "history" would be every
  /// blank manual entry in the ledger, whatever each was for. The same reason
  /// `RecurrenceDetector` refuses a blank group key.
  private func fromHistory(_ row: Transaction) throws -> CategorySuggestion? {
    let description = row.normalizedDescription
    guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let rowID = row.id

    let siblings = try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.normalizedDescription == description && $0.id != rowID && $0.categoryID != nil
        }))

    var counts: [UUID: Int] = [:]
    for sibling in siblings {
      guard let categoryID = sibling.categoryID else { continue }
      counts[categoryID, default: 0] += 1
    }

    let ranked = counts.sorted { lhs, rhs in
      if lhs.value != rhs.value { return lhs.value > rhs.value }
      return lhs.key.uuidString < rhs.key.uuidString
    }
    return ranked.first.map {
      CategorySuggestion(categoryID: $0.key, reason: .merchantHistory(matches: $0.value))
    }
  }

  /// Enabled rules, ordered once, first match wins. `firstMatch` re-checks
  /// `isEnabled` and uppercases the pattern itself.
  private func fromRules(_ row: Transaction) throws -> CategorySuggestion? {
    let rules = try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.isEnabled }))
      .map { RuleSnapshot($0) }
    guard
      let match = RuleEngine.firstMatch(
        normalizedDescription: row.normalizedDescription,
        in: RuleEngine.precedenceOrdered(rules))
    else { return nil }
    return CategorySuggestion(categoryID: match.categoryID, reason: .rule(ruleID: match.id))
  }

  private func row(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
