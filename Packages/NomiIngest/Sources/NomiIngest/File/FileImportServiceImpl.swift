import Foundation
import NomiCore

/// CSV + XLSX (CoreXLSX) bank-statement import. Content-sniffs before
/// trusting the file extension: many Indian bank ".xls" downloads are HTML
/// tables, parsed via SwiftSoup; a true legacy BIFF `.xls` throws
/// `.unsupportedLegacyXLS` (R7).
///
/// Mapped rows are handed to `IngestPipeline` (via `DraftIngesting`, same
/// seam `MailSyncEngine` uses) as `TransactionDraft`s — the pipeline's own
/// dedupe is what makes re-importing the same file idempotent; this service
/// no longer tracks that itself.
public final class FileImportServiceImpl: FileImportService, @unchecked Sendable {
  private let mappingStore: ColumnMappingStore
  private let pipeline: any DraftIngesting
  private let calendar: Calendar
  private let now: @Sendable () -> Date

  public init(
    mappingStore: ColumnMappingStore = InMemoryColumnMappingStore(),
    pipeline: any DraftIngesting,
    calendar: Calendar = {
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
      return cal
    }(),
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.mappingStore = mappingStore
    self.pipeline = pipeline
    self.calendar = calendar
    self.now = now
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

    let capturedAt = now()
    let drafts = parsed.map { row in
      TransactionDraft(
        date: row.date,
        descriptionText: row.descriptionText,
        amountMinor: row.amountMinor,
        direction: row.direction,
        accountID: accountID,
        source: .file,
        externalID: row.externalID,
        capturedAt: capturedAt
      )
    }

    // B2. One `ingest` call per 50 drafts, not one per file. The pipeline
    // serialises every call behind a single actor and holds that lock for the
    // whole batch, so a 5,000-row statement used to block a mail sync for the
    // length of 5,000 merge-candidate queries. Chunking releases the lock
    // between batches; the total work is unchanged.
    //
    // The batch size is `MailSyncEngine.fetchBatchSize` rather than a second
    // constant, because the two write paths queue against each other and a
    // different bound on each side would only be confusing.
    var created = 0
    var merged = 0
    for batch in drafts.slices(of: MailSyncEngine.fetchBatchSize) {
      let result = try await pipeline.ingest(batch)
      created += result.created
      merged += result.merged
    }
    return ImportSummary(created: created, merged: merged, skipped: skipped)
  }

  public func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {
    mappingStore.save(mapping, signature: signature, bankLabel: bankLabel)
  }
}
