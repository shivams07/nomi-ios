import Foundation

/// Pure function. Amounts are plain decimal (`1234.50`), never `\u{20B9}` or a
/// grouping separator — a CSV is opened in a spreadsheet, not displayed in the
/// app. Dates export as ISO-8601. Header row always present, even for zero rows.
public enum TransactionCSVExporter {
  static let header = "date,description,merchant,amount,direction,category_id,account_id"

  public static func export(_ transactions: [Transaction]) -> String {
    let rows = transactions.map {
      row(
        date: $0.date,
        descriptionText: $0.descriptionText,
        merchantName: $0.merchantName,
        amountMinor: $0.amountMinor,
        directionRaw: $0.directionRaw,
        categoryID: $0.categoryID,
        accountID: $0.accountID
      )
    }
    return ([header] + rows).joined(separator: "\n")
  }

  /// The per-row formatter, decoupled from `Transaction` (a SwiftData `@Model`)
  /// so it can be unit tested without constructing one.
  static func row(
    date: Date,
    descriptionText: String,
    merchantName: String?,
    amountMinor: Int,
    directionRaw: String,
    categoryID: UUID?,
    accountID: UUID?
  ) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]

    let isoDate = iso.string(from: date)
    let description = csvField(descriptionText)
    let merchant = csvField(merchantName ?? "")
    let amount = plainDecimal(amountMinor)
    let categoryIDField = categoryID?.uuidString ?? ""
    let accountIDField = accountID?.uuidString ?? ""
    return "\(isoDate),\(description),\(merchant),\(amount),\(directionRaw),\(categoryIDField),\(accountIDField)"
  }

  private static func plainDecimal(_ amountMinor: Int) -> String {
    let sign = amountMinor < 0 ? "-" : ""
    let magnitude = abs(amountMinor)
    let whole = magnitude / 100
    let fraction = magnitude % 100
    return "\(sign)\(whole).\(String(format: "%02d", fraction))"
  }

  private static func csvField(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
      return value
    }
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    return "\"\(escaped)\""
  }
}
