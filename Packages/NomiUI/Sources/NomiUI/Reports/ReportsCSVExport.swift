import Foundation
import NomiCore

/// Writes `TransactionCSVExporter`'s output to a temporary file for the share
/// sheet (`ReportsShareSheet`). `NomiUI` may not import `NomiIngest`, and this
/// unit is the designated caller per design §2.7. The exporter itself (plain
/// decimal amounts, no ₹, no grouping separator, header row always present)
/// is fully owned and tested in `NomiCore/Support/TransactionCSVExporter.swift`.
/// This type turns that `String` into a file, one fresh file per export tap.
/// The file is removed by `remove(_:)` when its share sheet closes (R12b, Y1).
enum ReportsCSVExport {
  enum ExportError: Error {
    case writeFailed
  }

  static func write(_ transactions: [Transaction], names: CSVNameMaps, periodLabel: String) throws -> URL {
    let csv = TransactionCSVExporter.export(transactions, names: names, timeZone: .current)
    let filename = "nomi-report-\(periodLabel)-\(UUID().uuidString).csv"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
      try csv.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      throw ExportError.writeFailed
    }
    return url
  }

  /// Removes a file `write` produced, once its share sheet has closed. A file
  /// that is already gone is not an error.
  static func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
  }
}
