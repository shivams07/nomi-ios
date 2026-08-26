import Foundation

/// A small RFC 4180 parser: quoted fields, embedded commas/newlines inside
/// quotes, and `""` as an escaped quote. Good enough for real bank exports;
/// no external dependency needed for plain CSV.
enum CSVParser {
  static func parse(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var field = ""
    var inQuotes = false
    var rowHasContent = false

    let chars = Array(text)
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if inQuotes {
        if c == "\"" {
          if i + 1 < chars.count, chars[i + 1] == "\"" {
            field.append("\"")
            i += 1
          } else {
            inQuotes = false
          }
        } else {
          field.append(c)
        }
      } else {
        switch c {
        case "\"":
          inQuotes = true
        case ",":
          currentRow.append(field)
          field = ""
          rowHasContent = true
        case "\n":
          currentRow.append(field)
          rows.append(currentRow)
          currentRow = []
          field = ""
          rowHasContent = false
        case "\r":
          break
        default:
          field.append(c)
          rowHasContent = true
        }
      }
      i += 1
    }
    if rowHasContent || !field.isEmpty || !currentRow.isEmpty {
      currentRow.append(field)
      rows.append(currentRow)
    }

    return rows.filter { row in
      !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}
