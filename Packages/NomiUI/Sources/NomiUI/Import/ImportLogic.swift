import Foundation
import NomiCore

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

/// Formats the import preview's row-count line, and is the single place that
/// decides whether the screen is in the "no transactions found" state.
enum ImportPreviewSummary {
  static func isEmpty(_ preview: ImportPreview) -> Bool {
    preview.parseableRowCount == 0
  }

  static func rowCountText(_ preview: ImportPreview) -> String {
    switch preview.parseableRowCount {
    case 0: return "No transactions found"
    case 1: return "1 transaction found"
    default: return "\(preview.parseableRowCount) transactions found"
    }
  }
}
