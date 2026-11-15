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
      guard let raw = field(row, mapping.amountColumn), let minor = parseAmountMinor(raw) else {
        return nil
      }
      return (abs(minor), minor < 0 ? .debit : .credit)

    case .separateColumns(let debitIndex, let creditIndex):
      guard let debit = separateCell(row, debitIndex), let credit = separateCell(row, creditIndex) else {
        return nil
      }
      if debit > 0 { return (debit, .debit) }
      if credit > 0 { return (credit, .credit) }
      return nil

    case .flagColumn(let index, let debitValues):
      guard let raw = field(row, mapping.amountColumn), let minor = parseAmountMinor(raw) else {
        return nil
      }
      let flag = field(row, index)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let direction: Direction = debitValues.contains(flag) ? .debit : .credit
      return (abs(minor), direction)
    }
  }

  /// One debit or credit cell of a separate-column row, as signed paise. A blank
  /// cell, or text that is not a number, reads as 0: bank files leave the column a
  /// row does not use empty or put a dash in it, and that is not a refusal. A
  /// number the rule refuses (beyond `AmountRules.maximumMinor`, or with more than
  /// two decimal places) is nil, so the whole row is refused rather than read from
  /// its other column.
  private static func separateCell(_ row: [String], _ index: Int) -> Int? {
    guard let raw = field(row, index) else { return 0 }
    switch parseAmount(raw) {
    case .success(let minor): return minor
    case .failure(.notANumber): return 0
    case .failure(.tooManyFractionDigits), .failure(.outOfRange): return nil
    }
  }

  /// A file amount in paise, or nil when it is refused. B7: this is `AmountText`,
  /// the rule manual entry uses (R8b, I-8), not a `Decimal` conversion. `Decimal`
  /// read "1.2.3" as 1.2, and its `Int` conversion silently truncated anything
  /// beyond `Int` (wave-1 Risk 10).
  private static func parseAmountMinor(_ raw: String) -> Int? {
    try? parseAmount(raw).get()
  }

  /// `AmountText.parse` on the cell, with one leading "+" allowed (B7 ruling):
  /// some bank exports write credits as "+1,000.00". The plus is removed here, not
  /// in `AmountText`, so manual entry is unchanged. A "+" followed by another sign
  /// ("+-5", "++5") is two signs and is refused.
  private static func parseAmount(_ raw: String) -> Result<Int, AmountTextRejection> {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("+") {
      text.removeFirst()
      if text.hasPrefix("+") || text.hasPrefix("-") { return .failure(.notANumber) }
    }
    return AmountText.parse(text, locale: amountLocale, allowNegative: true)
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
