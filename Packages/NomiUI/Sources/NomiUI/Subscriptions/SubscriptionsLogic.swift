import Foundation
import NomiCore

/// M5 (`nomi-ui-refresh` v5 §Subscriptions). The pure logic behind
/// `SubscriptionsScreen` — and, for the shared badge fallback only, the
/// Dashboard's `UpcomingCard` too — pulled out of both bodies for the same
/// reason `UpcomingRows` next door already is: `swift test` cannot reach a
/// SwiftUI `body` at all.
enum SubscriptionsSummary {
  /// Every row is a debit by construction (`RecurrenceDetector` only ever
  /// groups debits) — a plain sum, the same "no direction to branch on"
  /// rule `UpcomingCard`'s own doc comment already states.
  static func monthlyTotalMinor(_ series: [RecurringSeries]) -> Int {
    series.reduce(0) { $0 + $1.amountMinor }
  }

  /// The soonest series, `nil` for an empty list. `RecurringInsightsStore`'s
  /// own contract already guarantees `nextExpected`-ascending order, but
  /// this re-derives it rather than trusting `series.first` — the same
  /// defensive-by-convention choice `UpcomingRows.soonest` makes next door.
  static func next(_ series: [RecurringSeries]) -> RecurringSeries? {
    series.min { $0.nextExpected < $1.nextExpected }
  }
}

/// Buckets a series list by the calendar day of `nextExpected`, preserving
/// the store's own soonest-first order both across and within days.
///
/// Private to this screen rather than a `LedgerGrouping.byDay` edit:
/// `LedgerGrouping.byDay` is generic over `LedgerRow`, a protocol shaped for
/// ledger rows (`direction`, `categoryID`, `currencyCode`) that
/// `RecurringSeries` does not have and should not grow just to fit through
/// someone else's generic.
enum SubscriptionsGrouping {
  struct DayGroup: Identifiable {
    let day: Date
    let rows: [RecurringSeries]
    var id: Date { day }
  }

  static func byExpectedDay(_ series: [RecurringSeries], calendar: Calendar = .current) -> [DayGroup] {
    var order: [Date] = []
    var buckets: [Date: [RecurringSeries]] = [:]
    for item in series {
      let day = calendar.startOfDay(for: item.nextExpected)
      if buckets[day] == nil {
        buckets[day] = []
        order.append(day)
      }
      buckets[day]?.append(item)
    }
    return order.map { DayGroup(day: $0, rows: buckets[$0] ?? []) }
  }
}

/// The row-level strings — cadence and the "next charge" caption.
enum SubscriptionRowText {
  /// The literal `"Monthly"`. Not an enum with a `.monthly` case: today
  /// `RecurrenceDetector.intervalDays` (25...35) can find exactly one
  /// cadence, so a case for the one value it will ever produce would carry
  /// no information a `String` doesn't already. Widening to weekly/
  /// quarterly/annual is out of scope this wave (design doc §Why not the
  /// alternatives).
  static let cadence = "Monthly"

  /// "next in 3 days" / "next today" / "expected 2 days ago". The overdue
  /// phrasing never needs to describe anything further overdue than
  /// `RecurrenceDetector.intervalDays.upperBound` days past `nextExpected`
  /// — the detector drops a series as lapsed once it passes that point, so
  /// this never sees it.
  static func nextCharge(nextExpected: Date, now: Date, calendar: Calendar = .current) -> String {
    let startOfNext = calendar.startOfDay(for: nextExpected)
    let startOfNow = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: startOfNow, to: startOfNext).day ?? 0
    if days > 0 { return "next in \(days) day\(days == 1 ? "" : "s")" }
    if days < 0 { return "expected \(-days) day\(-days == 1 ? "" : "s") ago" }
    return "next today"
  }
}

/// The monogram fallback for a series with no category badge.
enum SubscriptionMonogram {
  /// First grapheme, uppercased; "?" for a blank label.
  static func letter(_ label: String) -> String {
    guard let first = label.first else { return "?" }
    return String(first).uppercased()
  }
}

/// The badge a row draws: the category badge when the series has one, else
/// the label's monogram. The same rule on both screens this wave draws a
/// `RecurringSeries` row on — `SubscriptionsScreen` and the Dashboard's
/// `UpcomingCard` — so it lives here once rather than twice. No logo
/// fetching of any kind (design doc §Approach, "Why not the alternatives").
enum SubscriptionBadge: Equatable {
  case category(CategoryBadge)
  case monogram(String)

  static func resolve(_ series: RecurringSeries) -> SubscriptionBadge {
    guard let category = series.category else {
      return .monogram(SubscriptionMonogram.letter(series.label))
    }
    return .category(category)
  }
}
