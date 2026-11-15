import Foundation

/// One row a dry run found new: what the Import screen shows under "First rows,
/// as Nomi reads them" (I-12).
public struct ImportDryRunRow: Sendable, Equatable, Identifiable {
  /// 0-based data-row index in the file.
  public let id: Int
  public let date: Date
  /// The raw narration cell, as `RowMapper` reads it.
  public let descriptionText: String
  public let amountMinor: Int
  public let direction: Direction

  public init(
    id: Int,
    date: Date,
    descriptionText: String,
    amountMinor: Int,
    direction: Direction
  ) {
    self.id = id
    self.date = date
    self.descriptionText = descriptionText
    self.amountMinor = amountMinor
    self.direction = direction
  }
}

/// What `FileImportService.dryRun` found in a file under a mapping, before any
/// write (I-12). The counts describe what `commit` does with the same file.
///
/// - `alreadyImportedCount`: parsed rows whose (source `.file`, externalID) is
///   already stored. Commit **merges** each one into the stored row. None is
///   created.
/// - `newCount`: every other parsed row. Commit **creates** it, or folds it into
///   an earlier row of the same file (same narration, amount and date under a
///   different reference). The Done screen's `created` and `merged` say which.
/// - `unreadable`: raw cells of rows that cannot be read, including rows whose
///   amount is outside `AmountRules`.
///
/// Invariants, asserted in `ImportDryRunTests`:
/// `newCount + alreadyImportedCount == created + merged` and
/// `unreadable.count == skipped`. Commit skips the same over-cap rows dry run
/// counts as unreadable (B7), so the second holds for every amount.
///
/// S11 copy: "new" here is not "will be added as a new row". The screen must not
/// say a row marked new is added as a new row, and must not say an already-known
/// row is skipped; it is merged.
public struct ImportDryRun: Sendable, Equatable {
  /// Parsed rows that are not already stored. Commit creates them or folds them
  /// into an earlier row of the same file (see above).
  public let newCount: Int
  /// Parsed rows whose (source `.file`, externalID) is already stored. Commit merges them.
  public let alreadyImportedCount: Int
  /// Raw cells of rows `RowMapper` could not map, or whose amount is outside
  /// `AmountRules`, in file order.
  public let unreadable: [[String]]
  /// The first five parsed rows that are new, in file order.
  public let sample: [ImportDryRunRow]

  public init(
    newCount: Int,
    alreadyImportedCount: Int,
    unreadable: [[String]],
    sample: [ImportDryRunRow]
  ) {
    self.newCount = newCount
    self.alreadyImportedCount = alreadyImportedCount
    self.unreadable = unreadable
    self.sample = sample
  }
}
