// clt-harness: include
import Foundation
import NomiCore

/// The line under a total that compares it with the earlier period (F2a, I-17).
/// Pure: no view, no clock. The caller passes the earlier period's label.
public enum NomiComparisonCopy {
  public enum Kind: Sendable {
    case spent
    case income
  }

  /// nil when there is no earlier period, or when either amount is negative
  /// (debits and credits are both positive sums, so this is a guard only).
  /// Zero earlier: "Nothing spent in <label> to compare". Equal: "Same as
  /// <label>". Lower or higher: "<amount> less than <label>" or "<amount> more
  /// than <label>", the amount being the difference.
  public static func line(kind: Kind, currentMinor: Int, priorMinor: Int?, priorLabel: String) -> String? {
    guard let priorMinor else { return nil }
    guard currentMinor >= 0, priorMinor >= 0 else { return nil }

    if priorMinor == 0 {
      switch kind {
      case .spent:
        return String(localized: "Nothing spent in \(priorLabel) to compare", bundle: .module)
      case .income:
        return String(localized: "Nothing received in \(priorLabel) to compare", bundle: .module)
      }
    }
    if currentMinor == priorMinor {
      return String(localized: "Same as \(priorLabel)", bundle: .module)
    }

    let amount = differenceText(abs(currentMinor - priorMinor))
    if currentMinor < priorMinor {
      return String(localized: "\(amount) less than \(priorLabel)", bundle: .module)
    }
    return String(localized: "\(amount) more than \(priorLabel)", bundle: .module)
  }

  /// The earlier period's name. A calendar month gives the prior month, in
  /// full ("October") or short ("Oct"; en_IN gives "Sept" for September). A
  /// financial year is "last year" either way. The selector never produces
  /// `trailingMonths` or `allTime` (no prior period), so those read as "last
  /// period" and are not reached by the screens.
  public static func priorLabel(period: InsightPeriod, short: Bool, calendar: Calendar) -> String {
    switch period {
    case .month(let year, let month):
      let prior = month == 1 ? (year: year - 1, month: 12) : (year: year, month: month - 1)
      if short {
        return shortMonthNames[prior.month - 1]
      }
      var components = DateComponents()
      components.year = prior.year
      components.month = prior.month
      components.day = 1
      let date = calendar.date(from: components) ?? Date()
      // Read the date back in the calendar's own zone, as DashboardPeriod does:
      // at the process default, a zone west of the calendar's names the month before.
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_IN")
      formatter.calendar = calendar
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = "MMMM"
      return formatter.string(from: date)
    case .financialYear:
      return String(localized: "last year", bundle: .module)
    case .trailingMonths, .allTime:
      return String(localized: "last period", bundle: .module)
    }
  }

  /// en_IN short month names, fixed here rather than read from ICU: the ICU on
  /// some toolchains gives "Sep" for September, and the copy reads "Sept".
  private static let shortMonthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sept", "Oct", "Nov", "Dec",
  ]

  /// Whole rupees when the difference is whole ("₹14,855"), two decimals
  /// otherwise ("₹1.50"). en_IN grouping, so lakhs read as lakhs.
  private static func differenceText(_ minor: Int) -> String {
    let whole = minor % 100 == 0
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.minimumFractionDigits = whole ? 0 : 2
    formatter.maximumFractionDigits = whole ? 0 : 2
    return formatter.string(from: NSNumber(value: Double(minor) / 100)) ?? "₹\(minor / 100)"
  }
}
