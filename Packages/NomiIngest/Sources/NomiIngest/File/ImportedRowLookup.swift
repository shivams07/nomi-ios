import Foundation
import NomiCore

/// Reads the external IDs already stored, for the "already in Nomi" count of
/// `FileImportService.dryRun` (I-12). Reads only: nothing here writes.
public protocol ImportedRowLookup: Sendable {
  /// Every `externalID` held in any row's source references under `source`.
  func externalIDs(source: IngestSource) async throws -> Set<String>
}
