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
    // Once per file, not once per cell. A package with no readable styles part
    // has no date formats in it, and every cell reads exactly as it did before.
    let dateStyles = (try? file.parseStyles()).map { XLSXDateStyles($0) }
      ?? XLSXDateStyles(dateStyleIndexes: [])
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
        let columnIndex = Self.columnIndex(cell.reference.column.value)
        let text: String
        if let isoDate = dateStyles.isoDate(for: cell) {
          text = isoDate
        } else if let sharedStrings, let resolved = cell.stringValue(sharedStrings) {
          text = resolved
        } else {
          text = cell.value ?? ""
        }
        byColumn[columnIndex] = text
        maxColumn = max(maxColumn, columnIndex)
      }
      return (0...maxColumn).map { byColumn[$0] ?? "" }
    }
    return grid
  }

  /// "A" -> 0, "B" -> 1, ..., "Z" -> 25, "AA" -> 26, ... `ColumnReference`
  /// only exposes its letters (`value`) publicly, not the numeric index.
  private static func columnIndex(_ letters: String) -> Int {
    letters.unicodeScalars.reduce(0) { acc, scalar in
      acc * 26 + Int(scalar.value - UnicodeScalar("A").value + 1)
    } - 1
  }
}

/// Which cell styles in a workbook carry a date number format (M6).
///
/// A spreadsheet stores a date as a number — days since 1899-12-30, the time of
/// day as the fraction — and only the cell's style says it is a date. Read
/// without the style, every date cell arrived as its serial ("46113"),
/// `RowMapper` could map no row, and a real bank export imported nothing.
///
/// A date cell is written into the grid as `yyyy-MM-dd`, whatever the sheet
/// displayed. `RowMapper.parseDate` falls back to exactly that format, so a
/// preset's `dd/MM/yy` still reads its bank's `.xlsx`.
///
/// CoreXLSX's own `Cell.dateValue` is not used: it converts in
/// `TimeZone.autoupdatingCurrent`, so one file would import as different days
/// on two devices.
struct XLSXDateStyles {
  /// Indexes into `cellXfs` whose number format is a date or time.
  let dateStyleIndexes: Set<Int>

  init(dateStyleIndexes: Set<Int>) {
    self.dateStyleIndexes = dateStyleIndexes
  }

  init(_ styles: Styles) {
    let customCodes = Dictionary(
      (styles.numberFormats?.items ?? []).map { ($0.id, $0.formatCode) },
      uniquingKeysWith: { first, _ in first }
    )
    var indexes = Set<Int>()
    for (index, format) in (styles.cellFormats?.items ?? []).enumerated() {
      let id = format.numberFormatId
      // A workbook may redefine a built-in id; what it wrote wins.
      let isDate = customCodes[id].map(Self.isDateFormatCode) ?? Self.isBuiltInDateFormat(id)
      if isDate {
        indexes.insert(index)
      }
    }
    self.dateStyleIndexes = indexes
  }

  /// The built-in date and time formats: 14–22, the East Asian date formats
  /// 27–36, and the time formats 45–47.
  static func isBuiltInDateFormat(_ id: Int) -> Bool {
    (14...22).contains(id) || (27...36).contains(id) || (45...47).contains(id)
  }

  /// A custom format is a date when `y`, `d` or `h` appears outside a quoted
  /// literal. `m` alone decides nothing — it is months and minutes both.
  ///
  /// Bracketed sections are skipped as well as quoted ones, and a
  /// backslash-escaped character is a literal: `[Red]#,##0.00` carries a `d`
  /// that is a colour, not a day.
  static func isDateFormatCode(_ code: String) -> Bool {
    var inQuotes = false
    var inBrackets = false
    var escaped = false
    for character in code.lowercased() {
      if escaped {
        escaped = false
        continue
      }
      switch character {
      case "\"":
        inQuotes.toggle()
      case "\\" where !inQuotes:
        escaped = true
      case "[" where !inQuotes:
        inBrackets = true
      case "]" where !inQuotes:
        inBrackets = false
      case "y", "d", "h":
        // Not `case "y", "d", "h" where …`: a `where` clause binds to the last
        // pattern only, and would leave the `d` in `[Red]` reading as a day.
        if !inQuotes && !inBrackets {
          return true
        }
      default:
        break
      }
    }
    return false
  }

  /// `yyyy-MM-dd` for a numeric cell in a date style; `nil` for every other
  /// cell, which is then read as it always was.
  ///
  /// A serial below 1 is a time with no date, and is left as the number.
  func isoDate(for cell: Cell) -> String? {
    guard let style = cell.styleIndex, dateStyleIndexes.contains(style) else { return nil }
    guard cell.type == nil || cell.type == .number else { return nil }
    guard let raw = cell.value, let serial = Double(raw), serial.isFinite, serial >= 1 else {
      return nil
    }
    return Self.isoDate(serial: serial)
  }

  /// Whole days after 1899-12-30; the time of day is dropped, as a statement's
  /// date column is a date. The arithmetic is in UTC because the serial is a
  /// wall-clock date with no zone attached: counting days in a zone that
  /// observes daylight saving could move it across midnight.
  static func isoDate(serial: Double) -> String? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    guard
      let epoch = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)),
      let day = calendar.date(byAdding: .day, value: Int(serial.rounded(.down)), to: epoch)
    else { return nil }

    let parts = calendar.dateComponents([.year, .month, .day], from: day)
    guard let year = parts.year, let month = parts.month, let dayOfMonth = parts.day else {
      return nil
    }
    return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
  }
}
