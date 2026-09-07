import Foundation

/// Pure function. Amounts are plain decimal (`1234.50`), never `\u{20B9}` or a
/// grouping separator — a CSV is opened in a spreadsheet, not displayed in the
/// app. Dates export as ISO-8601. Header row always present, even for zero rows.
public enum TransactionCSVExporter {
  static let header = "date,description,merchant,amount,currency,direction,category,account,source,needs_review,merged_count,upi_kind,counterparty_vpa,note"

  public static func export(_ rows: [Transaction], names: CSVNameMaps) -> String {
    let csvRows = rows.map {
      row(
        date: $0.date,
        descriptionText: $0.descriptionText,
        merchantName: $0.merchantName,
        amountMinor: $0.amountMinor,
        currencyCode: $0.currencyCode,
        directionRaw: $0.directionRaw,
        categoryName: resolvedName(for: $0.categoryID, in: names.categories),
        accountName: resolvedName(for: $0.accountID, in: names.accounts),
        sourceRaw: $0.sourceRaw,
        needsReview: $0.needsReview,
        mergedCount: $0.mergedCount,
        upiKindRaw: $0.upiKindRaw,
        counterpartyVPA: $0.counterpartyVPA,
        note: $0.note
      )
    }
    return ([header] + csvRows).joined(separator: "\n")
  }

  /// Split out of `export` so the "unknown id -> empty string" rule is
  /// testable on its own, without constructing a `Transaction` (`@Model`
  /// instances crash `swift test` outside a `#Preview` body).
  static func resolvedName(for id: UUID?, in names: [UUID: String]) -> String {
    id.flatMap { names[$0] } ?? ""
  }

  /// The per-row formatter, decoupled from `Transaction` (a SwiftData `@Model`)
  /// so it can be unit tested without constructing one.
  static func row(
    date: Date,
    descriptionText: String,
    merchantName: String?,
    amountMinor: Int,
    currencyCode: String,
    directionRaw: String,
    categoryName: String,
    accountName: String,
    sourceRaw: String,
    needsReview: Bool,
    mergedCount: Int,
    upiKindRaw: String?,
    counterpartyVPA: String?,
    note: String?
  ) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]

    let isoDate = iso.string(from: date)
    let description = csvField(descriptionText)
    let merchant = csvField(merchantName ?? "")
    // Amount never passes through `csvField` — a negative amount's leading
    // `-` would otherwise trip the OWASP-injection prefix meant for text.
    let amount = plainDecimal(amountMinor)
    let currency = csvField(currencyCode)
    let direction = csvField(directionRaw)
    let category = csvField(categoryName)
    let account = csvField(accountName)
    let source = csvField(sourceRaw)
    let needsReviewField = csvField(needsReview ? "true" : "false")
    let mergedCountField = csvField(String(mergedCount))
    let upiKind = csvField(upiKindRaw ?? "")
    let vpa = csvField(counterpartyVPA ?? "")
    let noteField = csvField(note ?? "")
    return "\(isoDate),\(description),\(merchant),\(amount),\(currency),\(direction),\(category),\(account),\(source),\(needsReviewField),\(mergedCountField),\(upiKind),\(vpa),\(noteField)"
  }

  private static func plainDecimal(_ amountMinor: Int) -> String {
    let sign = amountMinor < 0 ? "-" : ""
    let magnitude = abs(amountMinor)
    let whole = magnitude / 100
    let fraction = magnitude % 100
    return "\(sign)\(whole).\(String(format: "%02d", fraction))"
  }

  /// Standard CSV quoting plus the OWASP formula-injection mitigation: a
  /// field beginning with `=`, `+`, `-`, `@`, tab or CR is prefixed with a
  /// leading `'` before the usual comma/quote/newline quoting is applied, so
  /// a spreadsheet never interprets an exported cell as a formula.
  private static func csvField(_ value: String) -> String {
    var value = value
    if let first = value.first, "=+-@\t\r".contains(first) {
      value = "'\(value)"
    }
    guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
      return value
    }
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}

/// Category/account display names keyed by id, so the exporter never needs
/// to know how those stores are fetched — `ReportsScreen` builds this from
/// its own `@Query` results.
public struct CSVNameMaps: Sendable {
  public let categories: [UUID: String]
  public let accounts: [UUID: String]

  public init(categories: [UUID: String], accounts: [UUID: String]) {
    self.categories = categories
    self.accounts = accounts
  }
}
