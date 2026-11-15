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
  /// No longer read by `dryRun` (I-12 Amendment 1): the dry run asks the
  /// pipeline, which compares against the store itself. Kept so the composition
  /// root's call compiles; removed by the unit that next owns `AppEnvironment`.
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

  /// Counts what `commit` would do with this file, and writes nothing (I-12,
  /// Amendment 1). The counts come from the pipeline's own ingest loop run by
  /// `simulate`, over the same drafts `commit` builds, so dry run and commit agree
  /// field by field with no write in between. A row is parsed here exactly when
  /// commit would parse it (the same `RowMapper.mapAll` call and the same amount
  /// rule).
  public func dryRun(_ url: URL, mapping: ColumnMapping) async throws -> ImportDryRun {
    let file = try FileReader.read(url: url)
    let signature = FormatSignature.make(headers: file.headers)

    let mapped = RowMapper.mapAll(
      rows: file.dataRows, mapping: mapping, formatSignature: signature, calendar: calendar
    )

    // A row is unreadable when RowMapper cannot map it, or when its amount is
    // outside AmountRules. Commit applies the same rule (see `commit`), so the
    // rows it skips are exactly these (B7).
    var parsed: [(index: Int, row: ParsedRow)] = []
    var unreadable: [[String]] = []
    for (index, entry) in mapped.enumerated() {
      if let row = entry, AmountRules.isValidTransactionAmount(row.amountMinor) {
        parsed.append((index: index, row: row))
      } else {
        unreadable.append(file.dataRows[index])
      }
    }

    // Accounts are not part of the match (DedupeMatcher keys on amount, direction,
    // date and normalized text), so the dry run's nil account gives commit's counts.
    let capturedAt = now()
    let drafts = parsed.map { draft(for: $0.row, accountID: nil, capturedAt: capturedAt) }
    let result = try await pipeline.simulate(drafts)

    let createdIDs = Set(result.createdIDs)
    let repeatInFile = result.mergeTargetIDs.filter { createdIDs.contains($0) }.count

    var sample: [ImportDryRunRow] = []
    for draftIndex in result.createdDraftIndexes.prefix(5) {
      let entry = parsed[draftIndex]
      sample.append(
        ImportDryRunRow(
          id: entry.index,
          date: entry.row.date,
          descriptionText: entry.row.descriptionText,
          amountMinor: entry.row.amountMinor,
          direction: entry.row.direction
        )
      )
    }

    return ImportDryRun(
      createCount: result.created,
      matchExistingCount: result.merged - repeatInFile,
      repeatInFileCount: repeatInFile,
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
    // B7. A row is skipped when RowMapper cannot map it, or when its amount is
    // outside AmountRules: the rule manual entry uses, and the one `dryRun` counts
    // as unreadable. Skipped rows are counted in `skipped` and never reach the
    // pipeline. `ImportSummary` carries no reason field, so the reason is the rule
    // itself (see the PR).
    let parsed = mapped.compactMap { $0 }.filter { AmountRules.isValidTransactionAmount($0.amountMinor) }
    let skipped = mapped.count - parsed.count

    guard !parsed.isEmpty else {
      throw ImportError.noParseableRows
    }

    let capturedAt = now()
    let drafts = parsed.map { draft(for: $0, accountID: accountID, capturedAt: capturedAt) }

    // B2. One `ingest` call per 50 drafts, not one per file. The pipeline
    // serialises every call behind a single actor and holds that lock for the
    // whole batch, so a 5,000-row statement used to block a mail sync for the
    // length of 5,000 merge-candidate queries. Chunking releases the lock
    // between batches; the total work is unchanged.
    //
    // The batch size is `MailSyncEngine.fetchBatchSize` rather than a second
    // constant, because the two write paths queue against each other and a
    // different bound on each side would only be confusing.
    //
    // I-12 Amendment 1: a repeat that folds into a row an earlier batch created
    // is a repeat in this file, not a match with Nomi. So each batch's merge
    // targets are checked against every row this import has created so far.
    var created = 0
    var merged = 0
    var repeatedInFile = 0
    var createdIDs: Set<UUID> = []
    for batch in drafts.slices(of: MailSyncEngine.fetchBatchSize) {
      let result = try await pipeline.ingest(batch)
      created += result.created
      merged += result.merged
      createdIDs.formUnion(result.createdIDs)
      repeatedInFile += result.mergeTargetIDs.filter { createdIDs.contains($0) }.count
    }
    return ImportSummary(
      created: created,
      merged: merged,
      skipped: skipped,
      matchedExisting: merged - repeatedInFile,
      repeatedInFile: repeatedInFile
    )
  }

  public func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws {
    mappingStore.save(mapping, signature: signature, bankLabel: bankLabel)
  }

  /// The draft `commit` builds for one parsed row. Dry run builds the same one,
  /// so the pipeline sees the same input on both paths.
  private func draft(for row: ParsedRow, accountID: UUID?, capturedAt: Date) -> TransactionDraft {
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
}
