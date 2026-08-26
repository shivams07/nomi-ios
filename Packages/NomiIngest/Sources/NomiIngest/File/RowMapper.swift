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
  /// `nil` means the row could not be mapped (bad date, bad amount, or a
  /// row shorter than the mapping requires) and should count as `skipped`.
  static func map(
    row: [String],
    rowIndex: Int,
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
      externalID = "\(formatSignature):\(rowIndex)"
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
      let debit = field(row, debitIndex).flatMap(parseAmountMinor) ?? 0
      let credit = field(row, creditIndex).flatMap(parseAmountMinor) ?? 0
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

  /// Parses a plain decimal amount string (optionally with `,` grouping
  /// separators) into paise, via `Decimal` — never `Double` (R9).
  private static func parseAmountMinor(_ raw: String) -> Int? {
    let cleaned = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: ",", with: "")
    guard !cleaned.isEmpty, let decimal = Decimal(string: cleaned) else { return nil }
    let minor = decimal * 100
    var rounded = Decimal()
    var mutableMinor = minor
    NSDecimalRound(&rounded, &mutableMinor, 0, .plain)
    return NSDecimalNumber(decimal: rounded).intValue
  }

  private static func parseDate(_ raw: String, format: String) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
    formatter.dateFormat = format
    return formatter.date(from: trimmed)
  }
}
