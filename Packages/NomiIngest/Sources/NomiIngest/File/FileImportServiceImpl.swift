import Foundation
import NomiCore

/// CSV + XLSX (CoreXLSX) bank-statement import. Content-sniffs before
/// trusting the file extension: many Indian bank ".xls" downloads are HTML
/// tables, parsed via SwiftSoup; a true legacy BIFF `.xls` throws
/// `.unsupportedLegacyXLS` (R7).
///
/// Produces mapped rows only — never writes a `Transaction` to the store.
/// `ImportDedupeStore` is this unit's stand-in for the real write path
/// (U4's `IngestSink`, not yet built) so that re-importing the same file is
/// still idempotent within this service's lifetime.
public final class FileImportServiceImpl: FileImportService, @unchecked Sendable {
  private let mappingStore: ColumnMappingStore
  private let dedupeStore: ImportDedupeStore
  private let calendar: Calendar

  public init(
    mappingStore: ColumnMappingStore = InMemoryColumnMappingStore(),
    dedupeStore: ImportDedupeStore = InMemoryImportDedupeStore(),
    calendar: Calendar = {
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
      return cal
    }()
  ) {
    self.mappingStore = mappingStore
    self.dedupeStore = dedupeStore
    self.calendar = calendar
  }

  public func inspect(_ url: URL) async throws -> ImportPreview {
    let file = try FileReader.read(url: url)
    let signature = FormatSignature.make(headers: file.headers)

    var suggestedMapping: ColumnMapping?
    var detectedBankLabel: String?

    if let saved = mappingStore.mapping(forSignature: signature) {
      suggestedMapping = saved.mapping
      detectedBankLabel = saved.bankLabel
    } else if let preset = BankPresets.matching(headers: file.headers) {
      suggestedMapping = preset.mapping
      detectedBankLabel = preset.bankLabel
    }

    let parseableRowCount: Int
    if let mapping = suggestedMapping {
      parseableRowCount = file.dataRows.enumerated().reduce(into: 0) { count, element in
        let (index, row) = element
        if RowMapper.map(row: row, rowIndex: index, mapping: mapping, formatSignature: signature, calendar: calendar) != nil {
          count += 1
        }
      }
    } else {
      parseableRowCount = 0
    }

    return ImportPreview(
      formatSignature: signature,
      detectedBankLabel: detectedBankLabel,
      suggestedMapping: suggestedMapping,
      headers: file.headers,
      sampleRows: Array(file.dataRows.prefix(5)),
      parseableRowCount: parseableRowCount
    )
  }

  public func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary {
    let file = try FileReader.read(url: url)
    let signature = FormatSignature.make(headers: file.headers)

    var parsed: [ParsedRow] = []
    var skipped = 0
    for (index, row) in file.dataRows.enumerated() {
      if let mapped = RowMapper.map(row: row, rowIndex: index, mapping: mapping, formatSignature: signature, calendar: calendar) {
        parsed.append(mapped)
      } else {
        skipped += 1
      }
    }

    guard !parsed.isEmpty else {
      throw ImportError.noParseableRows
    }

    // Two rows in the SAME file sharing a dedupeKey (e.g. a duplicated export
    // row) only count once each: the first occurrence is "created", the rest
    // "merged" — exactly like merging against a prior import.
    var seenThisRun: Set<String> = []
    var created = 0
    var merged = 0
    for row in parsed {
      let alreadyKnown = seenThisRun.contains(row.dedupeKey)
        || !dedupeStore.containsAny(of: [row.dedupeKey]).isEmpty
      if alreadyKnown {
        merged += 1
      } else {
        created += 1
        seenThisRun.insert(row.dedupeKey)
      }
    }
    dedupeStore.record(seenThisRun)

    return ImportSummary(created: created, merged: merged, skipped: skipped)
  }

  public func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {
    mappingStore.save(mapping, signature: signature, bankLabel: bankLabel)
  }
}
