import Foundation

/// The edit half of a transaction. Separate from `TransactionStore` so the
/// detail screen and the account-binding work (`park/account-binding-loop`)
/// can land on independent branches: `TransactionStore` has no `update`, and
/// adding one would touch `Stores.swift`/`SwiftDataTransactionStore.swift`/
/// `FakeTransactionStore.swift`, files that unit owns. Fold this into
/// `TransactionStore` once both have merged.
@MainActor
public protocol TransactionEditing: AnyObject {
  /// Rewrites the user-editable facts on any row, whatever its source.
  /// Re-derives `normalizedDescription` and `dedupeKey` from the new
  /// amount/date/description, with the NomiCore functions the pipeline uses.
  ///
  /// The key follows the edited-key rule (I-11 Amendment 1). A manual row keeps the
  /// natural key, the same one the pipeline would derive, so a manual row and
  /// a bank alert with equal fields still pair up under reconcile. Any other
  /// source (email, file) gets a key salted with its own id, so no other row can
  /// share it. Reconcile groups rows by equal key and deletes all but one, so a
  /// user-edited email or file row must never be grouped with another row by
  /// accident. Rows edited before this rule keep their natural keys; no
  /// migration.
  ///
  /// `note` (U24) is stored as-is and, per `Transaction.note`'s own doc,
  /// deliberately feeds neither derivation. `needsReview`, `categoryID`,
  /// `accountID`, `sourceRefs` and `mergedCount` are untouched.
  func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String, note: String?) throws

  /// DEC-05. Marks or unmarks a row as a transfer, in one write. Marking also
  /// marks the single free partner that `TransferRules.manualPartner` finds, in
  /// the same write; a partner is read back by its shared `transferGroupID`.
  /// Unmarking clears every row in the group and records `rejected` on the row
  /// touched. Never changes a balance: `accountSummaries` reads the rows, not
  /// the marks.
  func setTransfer(_ id: UUID, isTransfer: Bool) throws

  /// Flips direction. Throws `TransactionEditError.transferLeg` when the row `isTransfer` (unmark first).
  /// Re-derives `dedupeKey` by the edited-key rule (I-11 Amendment 1; direction is part of it). Reports the row's category to `didWrite`.
  /// No default: every conformer implements it, so none can silently drop the flip.
  func setDirection(_ id: UUID, to direction: Direction) throws
}

public enum TransactionEditError: Error, Sendable, Equatable {
  /// The row is a transfer leg. Unmark the transfer first; its direction is not edited.
  case transferLeg
}
