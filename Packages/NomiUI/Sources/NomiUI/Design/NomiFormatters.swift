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

  /// Formats a minor-unit amount for a foreign-currency row (U18). INR takes
  /// the unchanged path above; anything else goes through a fresh formatter
  /// with `currencyCode` set — locale `en_IN` still picks the symbol and
  /// fraction digits (JPY renders with none), since it's the user's own
  /// locale that decides how a foreign amount reads to them, not the
  /// currency's home locale.
  ///
  /// The symbol en_IN's ICU data actually renders for a non-INR code is
  /// plain ("$", not the "US$" a first guess might expect) with a space
  /// before the amount — verified against real `NumberFormatter` output
  /// (CI, twice, across two different construction approaches that
  /// produced byte-identical results) rather than assumed. Do not "fix"
  /// this back toward a hand-rolled "US$" without re-verifying on a real
  /// run; it is not a bug in this function.
  public static func amountString(minor: Int, currencyCode: String) -> String {
    guard currencyCode != "INR" else { return amountString(minor: minor) }
    let major = Double(abs(minor)) / 100
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    return formatter.string(from: NSNumber(value: major)) ?? "\(currencyCode) \(major)"
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

  /// Weekday, day and month: "Thu 5 Nov" (D19, the Activity day header).
  public static let weekdayDayMonth: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.dateFormat = "EEE d MMM"
    return formatter
  }()

  /// The day header for a group of rows, relative to `referenceDate` (D19):
  /// "Today" and "Yesterday", then "Thu 5 Nov" within the reference's calendar
  /// year, and "5 Nov 2025" for an earlier year. Ledger rows from this year do
  /// not need the year on every header; older rows do.
  public static func dayMonthAdaptive(_ date: Date, relativeTo referenceDate: Date) -> String {
    let calendar = Calendar(identifier: .gregorian)
    if calendar.isDate(date, inSameDayAs: referenceDate) {
      return String(localized: "Today", bundle: .module)
    }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
       calendar.isDate(date, inSameDayAs: yesterday) {
      return String(localized: "Yesterday", bundle: .module)
    }
    let dateYear = calendar.component(.year, from: date)
    let referenceYear = calendar.component(.year, from: referenceDate)
    return dateYear == referenceYear ? weekdayDayMonth.string(from: date) : dayMonthYear.string(from: date)
  }

  public static let relativeTime: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.unitsStyle = .abbreviated
    return formatter
  }()
}
