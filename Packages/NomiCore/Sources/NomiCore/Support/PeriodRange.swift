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
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    let start = calendar.date(byAdding: .month, value: -count, to: end)!
    return start..<end

  case .allTime:
    let start = Date.distantPast
    let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    return start..<end
  }
}
