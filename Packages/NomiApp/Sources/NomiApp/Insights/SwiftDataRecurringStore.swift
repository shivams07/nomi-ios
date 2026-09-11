import Foundation
import NomiCore
import SwiftData

/// The real `RecurringInsightsStore` (U17a): six months of debits, run through
/// `RecurrenceDetector`, cached like every other aggregate.
///
/// It is a separate store rather than a sixth method on `SwiftDataInsightsStore`
/// on purpose. That store answers questions about a period the caller chose;
/// this one has no period — the six-month window is the detector's requirement,
/// not the screen's, and a `recurringSeries(for: .month(...))` would be a
/// question nobody can answer. The two share the cache, so a write still clears
/// both at once.
///
/// Follows `SwiftDataInsightsStore`'s two rules:
///
/// 1. **The predicate does the narrowing.** Date window, direction and currency
///    are in the fetch, so SQLite never hands across the credits the detector
///    would only throw away. On a ledger with a year of salary and refunds in it
///    that is most of the rows.
/// 2. **The result is cached and dropped on any write.** Detection is a sort
///    and a grouping over every debit in the window; the dashboard re-renders
///    far more often than it is written to.
@MainActor
public final class SwiftDataRecurringStore: RecurringInsightsStore {
  /// How far back to look. Six months is four spare cycles past the three
  /// charges the rule needs — enough that a monthly subscription is detected
  /// even if the user connected mail two months ago and the backfill (also six
  /// months) is the only history there is.
  public static let windowMonths = 6

  private let context: ModelContext
  private let cache: InsightsCache
  private let calendar: Calendar
  private let now: () -> Date

  /// `calendar` defaults to `.current` deliberately, matching
  /// `SwiftDataInsightsStore`. This is a display aggregate, not a key: a user
  /// abroad should see their own day boundaries, and `NomiCalendar.india` is
  /// for values that must be identical on two devices (see its doc comment).
  public init(
    context: ModelContext,
    cache: InsightsCache,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.context = context
    self.cache = cache
    self.calendar = calendar
    self.now = now
  }

  public func recurringSeries() throws -> [RecurringSeries] {
    try cache.value(for: .recurring) {
      // One `now()` for the window and for the staleness check. Reading the
      // clock twice would let a series be fetched under one instant and judged
      // stale under another.
      let moment = now()
      let window = dateRange(for: .trailingMonths(Self.windowMonths), calendar: calendar, now: moment)
      let lower = window.lowerBound
      let upper = window.upperBound
      let debit = Direction.debit.rawValue
      // W1-13. A foreign run's amounts are in another currency's minor unit,
      // and every figure the insights screens show is rupees.
      let rupees = "INR"

      var descriptor = FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.date >= lower && $0.date < upper && $0.directionRaw == debit
            && $0.currencyCode == rupees
        },
        // Oldest first, which is the order the detector walks gaps in. Sorting
        // in SQLite rather than in Swift for the same reason the ledger does:
        // the index is already there.
        sortBy: [SortDescriptor(\Transaction.date, order: .forward)]
      )
      descriptor.includePendingChanges = true

      return RecurrenceDetector.series(
        in: try context.fetch(descriptor).map { RecurrenceRow($0) },
        now: moment,
        calendar: calendar
      )
    }
  }
}

extension RecurrenceRow {
  /// Confined to this file, like `LedgerRow.init(_:)` next door: the detector
  /// must never mention a `@Model` type or it stops being runnable in NomiCore.
  init(_ transaction: Transaction) {
    self.init(
      date: transaction.date,
      amountMinor: transaction.amountMinor,
      directionRaw: transaction.directionRaw,
      normalizedDescription: transaction.normalizedDescription,
      merchantName: transaction.merchantName,
      descriptionText: transaction.descriptionText
    )
  }
}
