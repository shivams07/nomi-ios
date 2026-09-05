import Foundation

/// The edit half of a transaction. Separate from `TransactionStore` so the
/// detail screen and the account-binding work (`park/account-binding-loop`)
/// can land on independent branches: `TransactionStore` has no `update`, and
/// adding one would touch `Stores.swift`/`SwiftDataTransactionStore.swift`/
/// `FakeTransactionStore.swift`, files that unit owns. Fold this into
/// `TransactionStore` once both have merged.
@MainActor
public protocol TransactionEditing: AnyObject {
  /// Rewrites the three user-editable facts on any row, whatever its source.
  /// Re-derives `normalizedDescription` and `dedupeKey` from the new values —
  /// the same two NomiCore functions the pipeline and the manual store use, so
  /// the key stays byte-identical across writers. `needsReview`, `categoryID`,
  /// `accountID`, `sourceRefs` and `mergedCount` are untouched.
  func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String) throws
}
