import Foundation

/// A category the app would put on a row, and why.
///
/// UI refresh P3. The transaction sheet's "Suggested" row. Nomi has no model
/// behind this: the evidence is the user's own history for the merchant, then
/// the rule engine. The chip says "Suggested", never "AI".
public struct CategorySuggestion: Sendable, Equatable {
  public let categoryID: UUID
  public let reason: Reason

  public enum Reason: Sendable, Equatable {
    /// Other rows sharing this row's `normalizedDescription` with a category;
    /// majority wins, ties by count then id.
    case merchantHistory(matches: Int)
    /// The first enabled rule in precedence order whose glob matches
    /// `normalizedDescription`.
    case rule(ruleID: UUID)
  }

  public init(categoryID: UUID, reason: Reason) {
    self.categoryID = categoryID
    self.reason = reason
  }
}

/// A new contract file rather than a method on `TransactionStore`, because
/// NomiUI cannot import `NomiIngest`, where the rule engine lives, and
/// `Stores.swift` belongs to other units. Same shape as `TransactionEditing`.
@MainActor
public protocol CategorySuggesting: AnyObject {
  /// nil when the row is missing, when its `categorySource` is `.manual` (the user decided),
  /// when there is no evidence, or when the candidate equals the row's current `categoryID`.
  /// History is consulted before rules: the user's own filing of the same merchant outranks
  /// a glob, and any rule that could apply to a non-manual row already did at ingest.
  func suggestion(for transactionID: UUID) throws -> CategorySuggestion?
}
