import Foundation

/// Pure function. Amounts are plain decimal (`1234.50`), never `\u{20B9}` or a
/// grouping separator — a CSV is opened in a spreadsheet, not displayed in the
/// app. Dates export as ISO-8601. Header row always present, even for zero rows.
public enum TransactionCSVExporter {
  private static let header = "date,description,merchant,amount,direction,category_id,account_id"

  public static func export(_ transactions: [Transaction]) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]

    var lines = [header]
    for transaction in transactions {
      let date = iso.string(from: transaction.date)
      let description = csvField(transaction.descriptionText)
      let merchant = csvField(transaction.merchantName ?? "")
      let amount = plainDecimal(transaction.amountMinor)
      let direction = transaction.directionRaw
      let categoryID = transaction.categoryID?.uuidString ?? ""
      let accountID = transaction.accountID?.uuidString ?? ""
      lines.append("\(date),\(description),\(merchant),\(amount),\(direction),\(categoryID),\(accountID)")
    }
    return lines.joined(separator: "\n")
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
