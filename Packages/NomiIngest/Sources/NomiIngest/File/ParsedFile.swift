import Foundation
import NomiCore

struct ParsedFile {
  let headers: [String]
  let dataRows: [[String]]
}

/// The shared "turn bytes into a header + data grid" step used by both
/// `inspect` and `commit`, so they can never disagree about what a file
/// contains.
enum FileReader {
  static func read(url: URL) throws -> ParsedFile {
    let data = try Data(contentsOf: url)
    let format = try FormatSniffer.sniff(data: data)

    let grid: [[String]]
    switch format {
    case .legacyXLS:
      throw ImportError.unsupportedLegacyXLS

    case .xlsx:
      grid = try XLSXParser.parse(fileURL: url)

    case .htmlTable:
      guard let text = TextDecoder.decode(data) else {
        throw ImportError.unreadableEncoding
      }
      grid = try HTMLTableParser.parse(html: text)

    case .csv:
      guard let text = TextDecoder.decode(data) else {
        throw ImportError.unreadableEncoding
      }
      grid = CSVParser.parse(text)
    }

    guard let headerRow = grid.first else {
      return ParsedFile(headers: [], dataRows: [])
    }
    let dataRows = Array(grid.dropFirst()).filter { row in
      row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    return ParsedFile(headers: headerRow, dataRows: dataRows)
  }
}
