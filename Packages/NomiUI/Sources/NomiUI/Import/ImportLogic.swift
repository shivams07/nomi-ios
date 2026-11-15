import Foundation
import NomiCore
import UniformTypeIdentifiers

/// Named copy for every `ImportError` case — the U7 acceptance criteria asks
/// for named errors, not a single generic failure message.
enum ImportErrorMessage {
  static func text(for error: ImportError) -> String {
    switch error {
    case .unreadableEncoding:
      return "This file's text encoding isn't one Nomi can read. Try re-exporting it as UTF-8 CSV."
    case .unsupportedLegacyXLS:
      return "This is an older .xls file, which isn't supported. Re-save it as .xlsx or .csv and try again."
    case .malformedStructure(let reason):
      return "This file's rows don't line up: \(reason)."
    case .noParseableRows:
      return "No transactions were found in this file."
    }
  }
}

/// Whether a `ColumnMapping` is complete enough to commit: every referenced
/// column index must fall inside the file's actual header count, and the
/// three required columns must be distinct from one another.
enum ColumnMappingFormGate {
  static func isValid(_ mapping: ColumnMapping, headerCount: Int) -> Bool {
    let required = [mapping.dateColumn, mapping.descriptionColumn, mapping.amountColumn]
    guard required.allSatisfy({ $0 >= 0 && $0 < headerCount }) else { return false }
    guard Set(required).count == required.count else { return false }
    if let reference = mapping.referenceColumn {
      guard reference >= 0 && reference < headerCount else { return false }
    }
    switch mapping.directionStrategy {
    case .signedAmount:
      return true
    case .separateColumns(let debit, let credit):
      return debit >= 0 && debit < headerCount && credit >= 0 && credit < headerCount && debit != credit
    case .flagColumn(let index, let debitValues):
      return index >= 0 && index < headerCount && !debitValues.isEmpty
    }
  }
}

/// What the column-mapping sheet writes back to its binding when it closes
/// (UF1). Edits live in a draft; Cancel discards it and Save writes it back,
/// and Save only ever writes a draft that passes `ColumnMappingFormGate`. The
/// sheet's Save button is disabled on the same gate, so this adds no new
/// refusal, but it makes the Cancel decision reachable from a test.
enum ColumnMappingSheetOutcome {
  enum Close: Equatable {
    case save, cancel
  }

  /// The value to assign to the sheet's binding, or nil to leave it alone.
  static func writeBack(_ close: Close, draft: ColumnMapping, headerCount: Int) -> ColumnMapping? {
    switch close {
    case .cancel:
      return nil
    case .save:
      return ColumnMappingFormGate.isValid(draft, headerCount: headerCount) ? draft : nil
    }
  }
}

/// What `saveMapping` is called with — pulled out of the commit closure so a
/// test can reach the decision. `preview.formatSignature` is the file's real
/// signature (finding 5: the view body was calling `saveMapping` with the
/// file name instead, which meant every re-import of a renamed copy of the
/// same file missed its saved mapping). `bankLabel` falls back to the
/// signature itself when nothing was detected, so it never needs the file
/// name either.
enum SavedMappingKey {
  static func make(from preview: ImportPreview) -> (signature: String, bankLabel: String) {
    (preview.formatSignature, preview.detectedBankLabel ?? preview.formatSignature)
  }
}

/// M5: the file picker's allow-list. The sniffer decides what the bytes
/// actually are — a `.csv`-named file full of tab-separated rows still
/// parses — this only stops the picker from greying out files R7's sniffer
/// was already written to handle (xls, html) but the picker never offered.
enum ImportFileTypes {
  static let allowed: [UTType] = [
    .commaSeparatedText,
    .tabSeparatedText,
    .plainText,
    .spreadsheet,
    UTType(filenameExtension: "xlsx") ?? .data,
    UTType(filenameExtension: "xls") ?? .data,
    .html,
  ]
}

/// The Done screen's lines (`ImportDone` artboard, I-12 Amendment 1). Every number is
/// a count from commit's `ImportSummary`, never from the dry run, so a line can only
/// say what the import did. A zero count draws no line.
enum ImportDoneCopy {
  /// One line per non-zero count, in this order: "2 added", "2 matched transactions
  /// already in Nomi", "1 repeats in this file combined", "3 rows skipped".
  static func lines(_ summary: ImportSummary) -> [String] {
    var lines: [String] = []
    if summary.created > 0 {
      lines.append(String(localized: "\(summary.created) added", bundle: .module))
    }
    if summary.matchedExisting > 0 {
      lines.append(String(localized: "\(summary.matchedExisting) matched transactions already in Nomi", bundle: .module))
    }
    if summary.repeatedInFile > 0 {
      lines.append(String(localized: "\(summary.repeatedInFile) repeats in this file combined", bundle: .module))
    }
    if summary.skipped > 0 {
      lines.append(String(localized: "\(summary.skipped) rows skipped", bundle: .module))
    }
    return lines
  }

  /// The Done screen when commit reports no line at all.
  static let nothingAdded = String(localized: "Nothing was added.", bundle: .module)
}

/// The check screen's gate and copy (S11, I-12). Every count in copy is a catalog
/// plural, so a translation can pick its own forms. Nothing here adds up money.
enum ImportLogic {
  /// Import is offered only when at least one row will be created. Rows already in
  /// Nomi and repeats are folded on commit, so they never make Import available alone.
  static func canImport(createCount: Int) -> Bool {
    createCount > 0
  }

  /// The primary button: "Import 38 transactions", "Import 1 transaction". With
  /// nothing to create the button says so instead.
  static func importTitle(createCount: Int) -> String {
    guard createCount > 0 else {
      return String(localized: "Nothing new to import", bundle: .module)
    }
    return String(localized: "Import \(createCount) transactions", bundle: .module)
  }

  /// The warning under the tiles, naming the rows "Show them" lists.
  static func skippedNote(count: Int) -> String {
    String(localized: "\(count) rows could not be read and will be skipped.", bundle: .module)
  }

  /// The could-not-read note for a dry run: nil when no row is unreadable, otherwise the
  /// unreadable count and nothing else (pinned by test; a mutant that reads another count fails it).
  static func couldNotReadNote(for dry: ImportDryRun) -> String? {
    guard !dry.unreadable.isEmpty else { return nil }
    return skippedNote(count: dry.unreadable.count)
  }

  /// The repeat note: nil when no row repeats another row in the file. Otherwise the
  /// repeat count and nothing else.
  static func repeatNote(for dry: ImportDryRun) -> String? {
    guard dry.repeatInFileCount > 0 else { return nil }
    return String(
      localized: "\(dry.repeatInFileCount) rows repeat another row in this file and will be added once.",
      bundle: .module
    )
  }

  /// The explanation under the tiles when some rows are already in Nomi.
  static let alreadyInNomiNote = String(localized: "Rows already in Nomi are merged, not added again.", bundle: .module)

  /// The file card's second line: "HDFC Bank format · 4 Nov to 12 Nov". The range runs from the
  /// earliest to the latest date among the dry run's sample rows, and is left out when there is no sample.
  static func fileSubtitle(bankLabel: String?, sample: [ImportDryRunRow]) -> String {
    let format = bankLabel.map { String(localized: "\($0) format", bundle: .module) }
      ?? String(localized: "Unrecognized format", bundle: .module)
    guard let earliest = sample.map(\.date).min(), let latest = sample.map(\.date).max() else {
      return format
    }
    let range = String(localized: "\(dayMonth(earliest)) to \(dayMonth(latest))", bundle: .module)
    return "\(format) · \(range)"
  }

  /// A failed count (inspect of a known format, a dry run, or a lookup) never shows a zero.
  static let countFailure = String(localized: "Couldn’t read this file. Nothing was imported.", bundle: .module)

  /// A commit that throws after the counts were shown. Some batches may already be saved.
  static let commitFailure = String(
    localized: "The import didn’t finish, so some rows may already be saved. Your column mapping was not saved.",
    bundle: .module
  )

  /// The message for an inspect failure: the named `ImportError` copy when there is one.
  static func inspectFailure(_ error: Error) -> String {
    if let importError = error as? ImportError {
      return ImportErrorMessage.text(for: importError)
    }
    return countFailure
  }

  /// The mapping the sheet starts from when the format gave none: the three
  /// columns in their default places.
  static func fallbackMapping(for preview: ImportPreview) -> ColumnMapping {
    ColumnMapping(
      dateColumn: 0,
      descriptionColumn: min(1, max(preview.headers.count - 1, 0)),
      amountColumn: min(2, max(preview.headers.count - 1, 0)),
      referenceColumn: nil,
      directionStrategy: .signedAmount,
      dateFormat: "dd/MM/yyyy"
    )
  }

  /// The title of a sample row: the narration as read, trimmed. A blank narration reads
  /// "No narration". `TransactionRow.title` would say "Manual entry" there, which is false for a file row.
  static func sampleTitle(_ row: ImportDryRunRow) -> String {
    let narration = row.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    return narration.isEmpty ? String(localized: "No narration", bundle: .module) : narration
  }

  /// "12 Nov · UPI-BIGBASKET-631822904417": the line under a sample row's title.
  static func sampleSubtitle(_ row: ImportDryRunRow) -> String {
    "\(dayMonth(row.date)) · \(row.descriptionText)"
  }

  /// "2 Nov" in India time, the day the row's date falls on.
  private static func dayMonth(_ date: Date) -> String {
    dayMonthFormatter.string(from: date)
  }

  private static let dayMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.timeZone = NomiCalendar.india.timeZone
    formatter.dateFormat = "d MMM"
    return formatter
  }()
}

/// The raw cells of one row as one line: empty and whitespace-only cells are
/// dropped, the rest joined with " · ". Used for "Show them", so an empty cell
/// never reads as "· ·".
enum ImportSampleRow {
  static func text(_ cells: [String]) -> String {
    cells
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: " · ")
  }
}
