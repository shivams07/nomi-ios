import Foundation

/// The one calendar a dedupe key may be computed in.
public enum NomiCalendar {
  /// Gregorian, `Asia/Kolkata`, `en_US_POSIX`.
  ///
  /// `dedupeKey` folds a `Date` to a start-of-day, so the calendar's time zone
  /// decides which day an instant belongs to. Left at `.current` the same
  /// message ingested on a phone in IST and a Mac in UTC lands on two different
  /// days, produces two different keys, and reconcile cannot collapse the pair —
  /// the exact failure `MailDate.bankTimeZone` already argues against for
  /// parsing. Determinism has to hold on both sides of the key, not just one.
  ///
  /// IST is the deterministic choice and the correct one: India is the whole
  /// target market and Indian bank alerts are stamped IST.
  ///
  /// Display aggregation is deliberately not covered by this — a user abroad
  /// should see their own month boundaries. This constant is for keys.
  public static let india: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()
}
