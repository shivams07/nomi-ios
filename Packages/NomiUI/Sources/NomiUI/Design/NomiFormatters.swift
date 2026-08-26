import Foundation

/// Shared formatters so every screen agrees on ₹ and Indian digit grouping —
/// lakh/crore, not thousands. `en_IN` throughout, per the design doc.
public enum NomiFormatters {
  public static let currency: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter
  }()

  /// Formats a minor-unit amount (paise) into `₹1,23,456.00`-style text.
  /// Sign is never emitted here — callers that need a `+` for credits add it
  /// themselves, since direction carries the meaning, not this formatter.
  public static func amountString(minor: Int) -> String {
    let major = Double(abs(minor)) / 100
    return currency.string(from: NSNumber(value: major)) ?? "₹0.00"
  }

  /// The widest realistic amount, used to size the ledger's amount column.
  public static let widestRealisticAmount = "₹99,99,999.00"

  public static let dayMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.dateFormat = "d MMM"
    return formatter
  }()

  public static let dayMonthYear: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.dateFormat = "d MMM yyyy"
    return formatter
  }()

  public static let relativeTime: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.unitsStyle = .abbreviated
    return formatter
  }()
}
