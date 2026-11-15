import Foundation

/// The SOLE place Apr-Mar (or any period boundary) is computed. Every aggregate
/// query derives its predicate from this function — see design §2.3.
public func dateRange(for period: InsightPeriod, calendar: Calendar = .current, now: Date = Date()) -> Range<Date> {
  switch period {
  case .month(let year, let month):
    var startComponents = DateComponents()
    startComponents.year = year
    startComponents.month = month
    startComponents.day = 1
    let start = calendar.date(from: startComponents)!
    let end = calendar.date(byAdding: .month, value: 1, to: start)!
    return start..<end

  case .financialYear(let startingYear):
    var startComponents = DateComponents()
    startComponents.year = startingYear
    startComponents.month = 4
    startComponents.day = 1
    let start = calendar.date(from: startComponents)!
    let end = calendar.date(byAdding: .year, value: 1, to: start)!
    return start..<end

  case .trailingMonths(let count):
    // Whole calendar months: from the first of the month that contains `now`,
    // back `count - 1` months, to the start of tomorrow. `.trailingMonths(1)`
    // is this month so far. A count below 1 is read as 1.
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
    let start = calendar.date(byAdding: .month, value: -(max(count, 1) - 1), to: thisMonth)!
    return start..<end

  case .allTime:
    let start = Date.distantPast
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    return start..<end
  }
}
