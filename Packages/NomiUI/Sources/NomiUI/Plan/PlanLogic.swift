import Foundation
import NomiCore

/// The Plan tab's pure rules (S7). Plain functions over values, so the screen and
/// the model agree and the rules are tested without a view or a store.
enum PlanLogic {
  /// Where "today" sits in the month, from 0 to 1: the middle of today's day over
  /// the length of `month`. The pace tick on the hero bar sits here.
  static func pace(today: Date, month: (year: Int, month: Int), calendar: Calendar) -> Double {
    let day = calendar.component(.day, from: today)
    let days = daysInMonth(year: month.year, month: month.month, calendar: calendar)
    guard days > 0 else { return 0 }
    return (Double(day) - 1 + 0.5) / Double(days)
  }

  /// Days from today to the end of the month, today included: 14 November in a
  /// 30-day month leaves 17.
  ///
  /// Copy of S1b's `RemainingBudgetCard` rule. S1b owns it and will call this
  /// function once it lands; the two must not drift (see `PlanLogic.perDay`).
  static func daysLeft(today: Date, calendar: Calendar) -> Int {
    guard let range = calendar.range(of: .day, in: .month, for: today) else { return 0 }
    let day = calendar.component(.day, from: today)
    return range.count - day + 1
  }

  /// Whole rupees a day that keeps the month under budget: the remainder in
  /// whole rupees over the days left, floored. ₹1,321 over 17 days is ₹77 (₹77.7
  /// floored). Zero when over or with no days left.
  ///
  /// Copy of S1b's `RemainingBudgetCard` rule, owned by S1b. Duplicated here for
  /// now and to be consolidated when S1b lands.
  static func perDay(remainingMinor: Int, daysLeft: Int) -> Int {
    guard remainingMinor > 0, daysLeft > 0 else { return 0 }
    return (remainingMinor / 100) / daysLeft
  }

  /// The category most worth budgeting: the largest three-month spend that has no
  /// budget yet. The average is the three-month total over three, floored in
  /// minor units. The uncategorised sentinel is never suggested, and a category
  /// with no spend is not either. Ties go to whichever the store listed first.
  /// How many budget tiles sit across the sheet. One at accessibility sizes, so a
  /// category name never has to break inside a word in a half-width tile.
  static func budgetColumns(isAccessibilitySize: Bool) -> Int {
    isAccessibilitySize ? 1 : 2
  }

  static func suggestion(
    byCategory3m: [CategorySlice],
    budgeted: Set<UUID>
  ) -> (slice: CategorySlice, averageMinor: Int)? {
    let candidates = byCategory3m.filter {
      $0.id != NomiCore.Category.uncategorizedID && !budgeted.contains($0.id) && $0.totalMinor > 0
    }
    guard let best = candidates.max(by: { $0.totalMinor < $1.totalMinor }) else { return nil }
    return (best, best.totalMinor / 3)
  }

  /// A rupee figure as the row and the hero print it: whole rupees when there are no
  /// paise (`₹1,321`), two decimals otherwise, so a figure never silently drops
  /// paise. The sign is not printed; callers pass a magnitude.
  static func money(minor: Int) -> String {
    let magnitude = abs(minor)
    if magnitude % 100 == 0 {
      return wholeRupees.string(from: NSNumber(value: magnitude / 100)) ?? "₹\(magnitude / 100)"
    }
    return NomiFormatters.amountString(minor: magnitude)
  }

  /// "5 Dec", read in the calendar that built the date, so a date near midnight keeps its day.
  static func dayMonth(_ date: Date, calendar: Calendar) -> String {
    formatter(format: "d MMM", calendar: calendar).string(from: date)
  }

  /// "November", in the same calendar.
  static func monthName(_ date: Date, calendar: Calendar) -> String {
    formatter(format: "MMMM", calendar: calendar).string(from: date)
  }

  /// The first day of the month after `date`, for "resets 1 Dec".
  static func firstOfNextMonth(after date: Date, calendar: Calendar) -> Date? {
    guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return nil }
    return calendar.date(byAdding: .month, value: 1, to: start)
  }

  private static let wholeRupees: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencySymbol = "₹"
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter
  }()

  private static func formatter(format: String, calendar: Calendar) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.locale = Locale(identifier: "en_IN")
    formatter.dateFormat = format
    return formatter
  }

  private static func daysInMonth(year: Int, month: Int, calendar: Calendar) -> Int {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let first = calendar.date(from: components),
      let range = calendar.range(of: .day, in: .month, for: first)
    else { return 0 }
    return range.count
  }
}
