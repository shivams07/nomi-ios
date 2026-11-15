import Foundation
import NomiCore

/// R12b. Whether Home and Insights follow today. A screen that has not been
/// shown a picked period follows the clock, so after midnight it moves to the
/// new day or month. A picked period that contains today also keeps following
/// the clock. Any other picked period stays where the user put it.
enum PeriodAnchorPolicy {
  /// The anchor after a refresh. `now` while the screen follows today, else the
  /// anchor the user picked.
  static func anchorAfterRefresh(current: Date, followsToday: Bool, now: Date) -> Date {
    followsToday ? now : current
  }

  /// Whether a period picked from the pill contains `now`. The period comes
  /// from `ReportsPeriod.period`, and its boundaries from `NomiCore.dateRange`.
  static func followsToday(afterPicking anchor: Date, basis: PeriodBasis, now: Date, calendar: Calendar) -> Bool {
    let picked = ReportsPeriod.period(basis: basis, anchor: anchor, calendar: calendar)
    return dateRange(for: picked, calendar: calendar, now: now).contains(now)
  }
}
