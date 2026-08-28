import Foundation
import NomiCore

/// Writes `TransactionCSVExporter`'s output to a temporary file for
/// `ShareLink` to present — `NomiUI` may not import `NomiIngest`, and this
/// unit is the designated caller per design §2.7. The exporter itself (plain
/// decimal amounts, no ₹, no grouping separator, header row always present)
/// is fully owned and tested in `NomiCore/Support/TransactionCSVExporter.swift`;
/// this type's only job is turning that `String` into a file `ShareLink` can
/// hand to the share sheet, one write per export tap.
enum ReportsCSVExport {
  enum ExportError: Error {
    case writeFailed
  }

  static func write(_ transactions: [Transaction], filename: String = "nomi-report.csv") throws -> URL {
    let csv = TransactionCSVExporter.export(transactions)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    do {
      try csv.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      throw ExportError.writeFailed
    }
    return url
  }
}
