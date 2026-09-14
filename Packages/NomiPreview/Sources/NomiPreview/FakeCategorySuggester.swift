import Foundation
import NomiCore

/// Returns the one suggestion it was built with, for every row (UI refresh P3).
///
/// It has no rows, so it does not apply the contract's nil cases (`.manual`,
/// candidate equals current). The sheet mirrors those itself through
/// `SuggestionRow.isShown`, and a preview of a `.manual` row should show the
/// row hidden even when this returns a value.
@MainActor
public final class FakeCategorySuggester: CategorySuggesting {
  private let stubbed: CategorySuggestion?
  private let failure: Error?

  /// - Parameters:
  ///   - suggestion: pass `nil` for the no-evidence state.
  ///   - failure: thrown instead of returning, so the sheet's "an assist that
  ///     fails is an assist that is absent" path has something to preview.
  public init(suggestion: CategorySuggestion? = nil, failure: Error? = nil) {
    self.stubbed = suggestion
    self.failure = failure
  }

  public func suggestion(for transactionID: UUID) throws -> CategorySuggestion? {
    if let failure { throw failure }
    return stubbed
  }
}
