import CoreXLSX
import Foundation
import NomiCore

/// Reads the first worksheet of a `.xlsx` file into a row/column grid of
/// strings. CoreXLSX only reads from disk, so callers hand us a temp file URL.
enum XLSXParser {
  static func parse(fileURL: URL) throws -> [[String]] {
    guard let file = XLSXFile(filepath: fileURL.path) else {
      throw ImportError.malformedStructure(reason: "not a readable xlsx package")
    }

    guard
      let workbookPaths = try? file.parseWorkbooks(),
      let workbook = workbookPaths.first,
      let worksheetEntry = try? file.parseWorksheetPathsAndNames(workbook: workbook).first
    else {
      throw ImportError.malformedStructure(reason: "xlsx has no worksheet")
    }

    let sharedStrings = try? file.parseSharedStrings()
    let worksheet = try file.parseWorksheet(at: worksheetEntry.path)

    let rows = worksheet.data?.rows ?? []
    let grid: [[String]] = rows.map { row in
      // Cells carry their own column reference (e.g. "C3") and CoreXLSX omits
      // empty trailing cells, so index by reference rather than array position
      // — otherwise a blank Reference/Cheque No. column shifts everything
      // after it left.
      var byColumn: [Int: String] = [:]
      var maxColumn = 0
      for cell in row.cells {
        let columnIndex = cell.reference.column.index - 1
        byColumn[columnIndex] = cell.stringValue(sharedStrings) ?? ""
        maxColumn = max(maxColumn, columnIndex)
      }
      return (0...maxColumn).map { byColumn[$0] ?? "" }
    }
    return grid
  }
}
