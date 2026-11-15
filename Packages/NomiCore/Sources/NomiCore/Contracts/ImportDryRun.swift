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
/// write (I-12). Its counts describe the rows `commit` would import.
public struct ImportDryRun: Sendable, Equatable {
  /// Parsed rows whose externalID is not already in the store.
  public let newCount: Int
  /// Parsed rows whose (source `.file`, externalID) already exists.
  public let alreadyImportedCount: Int
  /// Raw cells of the rows `RowMapper` could not map, in file order.
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
