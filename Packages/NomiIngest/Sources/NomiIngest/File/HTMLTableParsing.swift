import Foundation
import NomiCore
import SwiftSoup

/// Parses the "many Indian bank .xls downloads are actually HTML" case (R6,
/// R7). Picks the largest `<table>` in the document — statement HTML usually
/// wraps the real data table in layout tables, so "most rows" beats "first
/// table found".
enum HTMLTableParser {
  static func parse(html: String) throws -> [[String]] {
    let document: Document
    do {
      document = try SwiftSoup.parse(html)
    } catch {
      throw ImportError.malformedStructure(reason: "unparseable HTML")
    }

    guard let tables = try? document.select("table"), !tables.array().isEmpty else {
      throw ImportError.malformedStructure(reason: "no table found in HTML")
    }

    var bestGrid: [[String]] = []
    for table in tables.array() {
      guard let trs = try? table.select("tr"), !trs.array().isEmpty else { continue }
      var grid: [[String]] = []
      for tr in trs.array() {
        guard let cells = try? tr.select("th, td"), !cells.array().isEmpty else { continue }
        let rowValues = cells.array().map { cell in
          (try? cell.text()) ?? ""
        }
        grid.append(rowValues)
      }
      if grid.count > bestGrid.count {
        bestGrid = grid
      }
    }
    return bestGrid
  }
}
