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
  /// Read by `dryRun` only. Nil means no store to compare against, so nothing
  /// is counted as already imported.
  private let lookup: (any ImportedRowLookup)?

  public init(
    mappingStore: ColumnMappingStore = InMemoryColumnMappingStore(),
    pipeline: any DraftIngesting,
    calendar: Calendar = {
      var cal = Calendar(identifier: .gregorian)
      cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
      return cal
    }(),
    now: @escaping @Sendable () -> Date = { Date() },
    lookup: (any ImportedRowLookup)? = nil
  ) {
    self.mappingStore = mappingStore
    self.pipeline = pipeline
    self.calendar = calendar
    self.now = now
    self.lookup = lookup
  }

  /// Counts what `commit` would import, and writes nothing (I-12). Maps the file
  /// with the same `RowMapper.mapAll` call `commit` makes, so a row is parsed here
  /// exactly when commit would parse it. Reads the already-imported IDs once; a
  /// lookup that throws propagates, and nothing is counted as zero by accident.
  public func dryRun(_ url: URL, mapping: ColumnMapping) async throws -> ImportDryRun {
    let file = try FileReader.read(url: url)
    let signature = FormatSignature.make(headers: file.headers)

    let mapped = RowMapper.mapAll(
      rows: file.dataRows, mapping: mapping, formatSignature: signature, calendar: calendar
    )

    // A row is unreadable when RowMapper cannot map it, or when its amount is
    // outside AmountRules (RowMapper has no upper bound, wave-1 Risk 10). The
    // second case is counted here so the screen never shows an amount it would
    // not accept; commit still imports such a row (see ImportDryRunTests).
    var parsed: [(index: Int, row: ParsedRow)] = []
    var unreadable: [[String]] = []
    for (index, entry) in mapped.enumerated() {
      if let row = entry, AmountRules.isValidTransactionAmount(row.amountMinor) {
        parsed.append((index: index, row: row))
      } else {
        unreadable.append(file.dataRows[index])
      }
    }

    // No lookup means no store to compare against: nothing is already imported.
    let stored: Set<String>
    if let lookup {
      stored = try await lookup.externalIDs(source: .file)
    } else {
      stored = []
    }

    var newCount = 0
    var sample: [ImportDryRunRow] = []
    for (index, row) in parsed where !stored.contains(row.externalID) {
      newCount += 1
      if sample.count < 5 {
        sample.append(
          ImportDryRunRow(
            id: index,
            date: row.date,
            descriptionText: row.descriptionText,
            amountMinor: row.amountMinor,
            direction: row.direction
          )
        )
      }
    }

    return ImportDryRun(
      newCount: newCount,
      alreadyImportedCount: parsed.count - newCount,
      unreadable: unreadable,
      sample: sample
    )
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
      parseableRowCount = RowMapper.mapAll(
        rows: file.dataRows, mapping: mapping, formatSignature: signature, calendar: calendar
      ).compactMap { $0 }.count
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

    let mapped = RowMapper.mapAll(
      rows: file.dataRows, mapping: mapping, formatSignature: signature, calendar: calendar
    )
    let parsed = mapped.compactMap { $0 }
    let skipped = mapped.count - parsed.count

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
