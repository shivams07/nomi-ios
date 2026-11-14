import Foundation

/// A small RFC 4180 parser: quoted fields, embedded commas/newlines inside
/// quotes, and `""` as an escaped quote. Rows end at CRLF, a lone CR or a lone
/// LF, so a file saved with any of the three splits the same way. Line breaks
/// inside quotes are normalised to "\n". Works on Unicode scalars, not
/// Characters, because "\r\n" is a single Character. Good enough for real bank
/// exports; no external dependency needed for plain CSV.
enum CSVParser {
  static func parse(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var field = String.UnicodeScalarView()
    var inQuotes = false
    var rowHasContent = false

    let scalars = Array(text.unicodeScalars)
    var i = 0
    while i < scalars.count {
      let c = scalars[i]
      if inQuotes {
        if c == "\"" {
          if i + 1 < scalars.count, scalars[i + 1] == "\"" {
            field.append("\"")
            i += 1
          } else {
            inQuotes = false
          }
        } else if c == "\r" {
          // CRLF and a lone CR each become a single "\n" inside quotes.
          if i + 1 < scalars.count, scalars[i + 1] == "\n" {
            i += 1
          }
          field.append("\n")
        } else {
          field.append(c)
        }
      } else {
        switch c {
        case "\"":
          inQuotes = true
        case ",":
          currentRow.append(String(field))
          field = String.UnicodeScalarView()
          rowHasContent = true
        case "\r", "\n":
          // A CRLF pair ends one row, not two.
          if c == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" {
            i += 1
          }
          currentRow.append(String(field))
          rows.append(currentRow)
          currentRow = []
          field = String.UnicodeScalarView()
          rowHasContent = false
        default:
          field.append(c)
          rowHasContent = true
        }
      }
      i += 1
    }
    if rowHasContent || !field.isEmpty || !currentRow.isEmpty {
      currentRow.append(String(field))
      rows.append(currentRow)
    }

    return rows.filter { row in
      !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty)
    }
  }
}
