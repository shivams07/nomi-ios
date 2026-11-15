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
/// write (I-12, Amendment 1). The counts come from the pipeline's own ingest loop
/// run without writing, so they answer the question `commit` answers: with no
/// write in between, `commit` returns the same numbers for the same file.
///
/// - `createCount`: rows commit will create.
/// - `matchExistingCount`: rows commit will fold into a transaction already in
///   Nomi, including a row imported before (the same file row imported twice).
/// - `repeatInFileCount`: rows commit will fold into a row this same import
///   creates (a repeated line, or two references the matcher treats as one).
/// - `unreadable`: raw cells of rows that cannot be read, including rows whose
///   amount is outside `AmountRules`.
/// - `sample`: the first five rows that will be created, in file order.
///
/// Invariant, asserted in `ImportDryRunTests`:
/// `createCount + matchExistingCount + repeatInFileCount` equals the parsed rows.
public struct ImportDryRun: Sendable, Equatable {
  /// Rows commit will create.
  public let createCount: Int
  /// Rows commit will fold into a transaction already in Nomi.
  public let matchExistingCount: Int
  /// Rows commit will fold into a row this same import creates.
  public let repeatInFileCount: Int
  /// Raw cells of rows `RowMapper` could not map, or whose amount is outside
  /// `AmountRules`, in file order.
  public let unreadable: [[String]]
  /// The first five rows that will be created, in file order.
  public let sample: [ImportDryRunRow]

  public init(
    createCount: Int,
    matchExistingCount: Int,
    repeatInFileCount: Int,
    unreadable: [[String]],
    sample: [ImportDryRunRow]
  ) {
    self.createCount = createCount
    self.matchExistingCount = matchExistingCount
    self.repeatInFileCount = repeatInFileCount
    self.unreadable = unreadable
    self.sample = sample
  }
}
