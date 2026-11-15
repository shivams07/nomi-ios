import CryptoKit
import Foundation
import NomiCore

/// A single parsed, mapped transaction row — the file-import unit's version
/// of "`TransactionDraft`". Never touches the store; `FileImportServiceImpl`
/// only uses it to compute `ImportSummary` counts.
struct ParsedRow {
  let date: Date
  let descriptionText: String
  let amountMinor: Int
  let direction: Direction
  let externalID: String
  let dedupeKey: String
}

enum RowMapper {
  /// Every data row of one file, in file order. An element is `nil` when its
  /// row could not be mapped (bad date, bad amount, an amount outside
  /// `AmountRules` (B7), or a row shorter than the mapping requires) and counts
  /// as `skipped` in commit and as unreadable in dry run.
  ///
  /// This is the only way in, and it takes the whole file rather than a row,
  /// because a row's id depends on the rows before it (W1-11): `k` is how many
  /// byte-identical rows — fields joined by `|` — came earlier in the same
  /// file, mapped or not.
  static func mapAll(
    rows: [[String]],
    mapping: ColumnMapping,
    formatSignature: String,
    calendar: Calendar
  ) -> [ParsedRow?] {
    var seen: [String: Int] = [:]
    return rows.map { row in
      let rawRow = row.joined(separator: "|")
      let k = seen[rawRow, default: 0]
      seen[rawRow] = k + 1
      return map(
        row: row,
        rawRow: rawRow,
        k: k,
        mapping: mapping,
        formatSignature: formatSignature,
        calendar: calendar
      )
    }
  }

  private static func map(
    row: [String],
    rawRow: String,
    k: Int,
    mapping: ColumnMapping,
    formatSignature: String,
    calendar: Calendar
  ) -> ParsedRow? {
    guard let rawDate = field(row, mapping.dateColumn),
      let rawDescription = field(row, mapping.descriptionColumn)
    else { return nil }

    guard let date = parseDate(rawDate, format: mapping.dateFormat) else { return nil }

    guard let (amountMinor, direction) = resolveAmount(row: row, mapping: mapping) else {
      return nil
    }
    guard amountMinor != 0 else { return nil }

    let description = rawDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !description.isEmpty else { return nil }

    let externalID: String
    if let referenceColumn = mapping.referenceColumn,
      let rawReference = field(row, referenceColumn),
      !rawReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      externalID = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
      // L10. The row's content, not its index: in an overlapping statement the
      // same row sits at another index and must get the same id, so importing
      // it again is a no-op. Two identical rows in one file differ only in `k`,
      // so both are kept.
      let digest = SHA256.hash(data: Data(rawRow.utf8))
      let hex = digest.map { String(format: "%02x", $0) }.joined()
      externalID = "\(formatSignature):\(hex):\(k)"
    }

    let normalized = normalizeDescription(description)
    let dedupeKey = makeDedupeKey(
      date: date,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      normalizedDescription: normalized,
      calendar: calendar
    )

    return ParsedRow(
      date: date,
      descriptionText: description,
      amountMinor: amountMinor,
      direction: direction,
      externalID: externalID,
      dedupeKey: dedupeKey
    )
  }

  private static func field(_ row: [String], _ index: Int) -> String? {
    guard index >= 0, index < row.count else { return nil }
    return row[index]
  }

  private static func resolveAmount(row: [String], mapping: ColumnMapping) -> (Int, Direction)? {
    switch mapping.directionStrategy {
    case .signedAmount:
      guard let raw = field(row, mapping.amountColumn), let cell = readCell(raw),
        let direction = signedDirection(cell)
      else { return nil }
      return (abs(cell.minor), direction)

    case .separateColumns(let debitIndex, let creditIndex):
      guard let debit = separateCell(row, debitIndex, column: .debit),
        let credit = separateCell(row, creditIndex, column: .credit)
      else { return nil }
      if debit > 0 { return (debit, .debit) }
      if credit > 0 { return (credit, .credit) }
      return nil

    case .flagColumn(let index, let debitValues):
      guard let raw = field(row, mapping.amountColumn), let cell = readCell(raw) else { return nil }
      let flag = field(row, index)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let direction: Direction = debitValues.contains(flag) ? .debit : .credit
      // A Dr or Cr on the amount must agree with the flag it is read with.
      guard cell.suffix == nil || cell.suffix == direction else { return nil }
      return (abs(cell.minor), direction)
    }
  }

  /// One debit or credit cell of a separate-column row, as signed paise.
  ///
  /// B7 ruling: only a blank cell, "-", "–" or "—" reads as 0. Any other cell that
  /// is not a number refuses the whole row, so the other column is never read in
  /// its place. A Dr or Cr on the cell must agree with its column, and a sign must
  /// agree with a suffix. A number the rule refuses is nil for the same reason.
  private static func separateCell(_ row: [String], _ index: Int, column: Direction) -> Int? {
    guard let raw = field(row, index) else { return 0 }
    if placeholders.contains(raw.trimmingCharacters(in: .whitespacesAndNewlines)) { return 0 }
    guard let cell = readCell(raw), signedDirection(cell) != nil else { return nil }
    guard cell.suffix == nil || cell.suffix == column else { return nil }
    return cell.minor
  }

  /// A cell that stands for no amount: blank, a hyphen-minus, an en dash or an em dash.
  private static let placeholders: Set<String> = ["", "-", "\u{2013}", "\u{2014}"]

  /// One amount cell as the rules read it.
  private struct Cell {
    /// The magnitude, negative when the text has a leading "-".
    let minor: Int
    /// "-" is a debit, "+" a credit, and nil when the text has no sign.
    let sign: Direction?
    /// "Dr" or "Cr" at the end of the text, after optional whitespace.
    let suffix: Direction?
  }

  /// The Dr and Cr spellings file import accepts. Other cases, such as "dr", are refused.
  private static let suffixes: [(text: String, direction: Direction)] = [
    ("Cr.", .credit), ("CR", .credit), ("Cr", .credit),
    ("Dr.", .debit), ("DR", .debit), ("Dr", .debit),
  ]

  /// Reads one amount cell. The Dr or Cr suffix is stripped and the sign removed, and
  /// what is left goes to `AmountText.parse`, the rule manual entry uses. `AmountText`
  /// is not changed. Refused (nil) when the rest is not an amount, when a second sign
  /// follows the first, when a space sits between the sign and the number, or when the
  /// magnitude is beyond the cap.
  private static func readCell(_ raw: String) -> Cell? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    var suffix: Direction?
    if let match = suffixes.first(where: { text.hasSuffix($0.text) }) {
      text = String(text.dropLast(match.text.count)).trimmingCharacters(in: .whitespaces)
      suffix = match.direction
    }
    var sign: Direction?
    if let first = text.first, first == "+" || first == "-" {
      sign = first == "-" ? .debit : .credit
      text.removeFirst()
      // The sign is adjacent to the number: a second sign or a space here is refused.
      if let next = text.first, next == "+" || next == "-" || next.isWhitespace { return nil }
    }
    guard case .success(let magnitude) = AmountText.parse(text, locale: amountLocale, allowNegative: false)
    else { return nil }
    return Cell(minor: sign == .debit ? -magnitude : magnitude, sign: sign, suffix: suffix)
  }

  /// The direction a signed-column cell gives. No sign and no suffix is a credit, as it
  /// always was. Otherwise the sign or the suffix sets it. A sign and a suffix that
  /// disagree give nil, and the row is refused.
  private static func signedDirection(_ cell: Cell) -> Direction? {
    switch (cell.sign, cell.suffix) {
    case (nil, nil): return .credit
    case (let sign?, nil): return sign
    case (nil, let suffix?): return suffix
    case (let sign?, let suffix?): return sign == suffix ? sign : nil
    }
  }

  /// Pinned to en_US_POSIX so a file reads the same on every device: "." is the
  /// decimal separator and "," is grouping, as bank exports write them.
  private static let amountLocale = Locale(identifier: "en_US_POSIX")

  /// What `XLSXParser` writes for a real date cell.
  static let isoDateFormat = "yyyy-MM-dd"

  /// `format` first, then `isoDateFormat`, both in IST (W1-11).
  ///
  /// The fallback is what lets a preset read its own bank's `.xlsx`: the
  /// preset says `dd/MM/yy` because that is what the bank's CSV contains, but a
  /// date *cell* reaches the grid as ISO whatever the sheet displayed.
  /// `DateFormatter` is not lenient, so a mapped format that does not fit the
  /// string returns nil rather than a wrong date, and the fallback is tried.
  private static func parseDate(_ raw: String, format: String) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    for candidate in [format, isoDateFormat] {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
      formatter.dateFormat = candidate
      if let date = formatter.date(from: trimmed) {
        return date
      }
    }
    return nil
  }
}
