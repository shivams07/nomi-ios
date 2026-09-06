import Foundation

/// A value-typed view of the fields recurrence detection reads.
///
/// `LedgerRow` carries every one of these already and is deliberately not
/// reused: it lives in `NomiApp` (`InsightsAggregator.swift`), and NomiCore
/// cannot see NomiApp. Same device as `TransactionSnapshot` in the pipeline,
/// and for the same reason — the rule has to be runnable in a target that has
/// no `@Model` in it. `SwiftDataRecurringStore` fetches `Transaction` rows and
/// maps them across.
public struct RecurrenceRow: Sendable, Equatable {
  public let date: Date
  public let amountMinor: Int
  public let directionRaw: String
  public let normalizedDescription: String
  public let merchantName: String?
  public let descriptionText: String

  public init(
    date: Date,
    amountMinor: Int,
    directionRaw: String,
    normalizedDescription: String,
    merchantName: String?,
    descriptionText: String
  ) {
    self.date = date
    self.amountMinor = amountMinor
    self.directionRaw = directionRaw
    self.normalizedDescription = normalizedDescription
    self.merchantName = merchantName
    self.descriptionText = descriptionText
  }

  public var isDebit: Bool { directionRaw == Direction.debit.rawValue }
}

/// One run of debits that looks like a subscription.
public struct RecurringSeries: Sendable, Identifiable, Equatable {
  /// The `normalizedDescription` the rows were grouped by.
  ///
  /// Stable across syncs — `normalizeDescription` uppercases, strips digits and
  /// collapses whitespace, so the reference number that differs on every charge
  /// is already gone — which is what makes it usable as a `ForEach` id. A UUID
  /// minted per detection run would re-identify every row on every recompute.
  public let id: String

  /// What to show the user: the newest row's merchant, falling back to its
  /// description. The newest rather than the oldest because a merchant that
  /// renamed itself should read by its current name.
  public let label: String

  /// The median of the run, not the newest amount: a price change mid-run is
  /// what the ±10% band exists to tolerate, and the median is the value least
  /// moved by the outlier that tolerance let through.
  public let amountMinor: Int

  public let occurrences: Int
  public let lastDate: Date
  public let nextExpected: Date

  public init(
    id: String,
    label: String,
    amountMinor: Int,
    occurrences: Int,
    lastDate: Date,
    nextExpected: Date
  ) {
    self.id = id
    self.label = label
    self.amountMinor = amountMinor
    self.occurrences = occurrences
    self.lastDate = lastDate
    self.nextExpected = nextExpected
  }
}

/// Monthly-subscription detection, as a pure function over rows.
///
/// **This is a heuristic, and it is tuned to miss rather than to guess.** A
/// series is claimed only when three consecutive charges agree on both timing
/// and amount; weekly, fortnightly, quarterly and annual runs are out, as are
/// variable-amount ones (a utility bill), and so are credits — salary is
/// regular and is not something a user needs warned about. A false positive
/// puts a charge on the dashboard that will never arrive, which is worse than
/// showing nothing, so every ambiguous case resolves to nothing.
public enum RecurrenceDetector {
  /// Three, not two. Two dated rows describe exactly one interval, and one
  /// interval is not evidence of a period — any two debits a month apart would
  /// qualify.
  public static let minimumOccurrences = 3

  /// The gap band, in whole days. Wide enough for a monthly charge that lands
  /// on the 1st of a 28-day month and the 1st of a 31-day one, and for a
  /// weekend shifting a posting date, and narrow enough that a fortnightly or
  /// a quarterly run cannot fall inside it.
  public static let intervalDays = 25...35

  /// How far an individual charge may sit from the run's median, as a
  /// percentage. Covers a price rise or a tax change without admitting a run
  /// of unrelated debits that happen to share a description.
  public static let amountTolerancePercent = 10

  /// Debits only, grouped by `normalizedDescription`.
  ///
  /// - Parameters:
  ///   - rows: the caller's window. The detector does no date filtering of its
  ///     own beyond the staleness rule below; how far back to look is the
  ///     store's decision, not this function's.
  ///   - now: used for one thing — dropping a series whose next charge is
  ///     already overdue by a full interval. A cancelled subscription still has
  ///     three good charges inside a six-month window, and without this the
  ///     card would announce a payment "expected" months in the past as though
  ///     it were still coming.
  ///   - calendar: gaps are measured between start-of-day boundaries in this
  ///     calendar, so a charge posted at 23:50 and the next at 00:10 read as 30
  ///     days apart rather than 29-and-a-bit.
  /// - Returns: the detected series, `nextExpected` ascending, ties broken by
  ///   `id`. Sorted here rather than left to the caller because the grouping
  ///   below is a dictionary and its iteration order is not stable between
  ///   runs.
  public static func series(in rows: [RecurrenceRow], now: Date, calendar: Calendar) -> [RecurringSeries] {
    var groups: [String: [RecurrenceRow]] = [:]
    for row in rows where row.isDebit {
      let key = row.normalizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      // A blank key is not a group. Rows that normalize to nothing have no
      // description in common — they have no description at all — and letting
      // them share a bucket would invent a series out of unrelated charges.
      guard !key.isEmpty else { continue }
      groups[key, default: []].append(row)
    }

    let detected = groups.compactMap { key, group in
      series(id: key, rows: group.sorted { $0.date < $1.date }, now: now, calendar: calendar)
    }
    return detected.sorted { ($0.nextExpected, $0.id) < ($1.nextExpected, $1.id) }
  }

  /// One group, already sorted oldest first. `nil` means "not a series", and
  /// every rejection below returns it rather than a partial answer: a run that
  /// fails one test is not salvaged by dropping the row that failed it.
  private static func series(
    id: String,
    rows: [RecurrenceRow],
    now: Date,
    calendar: Calendar
  ) -> RecurringSeries? {
    guard rows.count >= minimumOccurrences, let newest = rows.last else { return nil }

    var gaps: [Int] = []
    for (earlier, later) in zip(rows, rows.dropFirst()) {
      guard
        let gap = calendar.dateComponents(
          [.day],
          from: calendar.startOfDay(for: earlier.date),
          to: calendar.startOfDay(for: later.date)
        ).day,
        intervalDays.contains(gap)
      else { return nil }
      gaps.append(gap)
    }

    let amounts = rows.map(\.amountMinor)
    let medianAmount = median(of: amounts)
    // A zero or negative median is not a subscription, and it would also make
    // the tolerance test below admit everything.
    guard medianAmount > 0 else { return nil }
    // Integer arithmetic rather than `Double(...) * 0.1`: the comparison is
    // exact, and an amount in minor units has no business becoming a Double.
    guard amounts.allSatisfy({ abs($0 - medianAmount) * 100 <= medianAmount * amountTolerancePercent })
    else { return nil }

    guard
      let nextExpected = calendar.date(byAdding: .day, value: median(of: gaps), to: newest.date),
      // Overdue by a whole interval on top of the expected date: the charge
      // stopped coming, so it is not upcoming.
      let lapsed = calendar.date(byAdding: .day, value: intervalDays.upperBound, to: nextExpected),
      lapsed >= now
    else { return nil }

    return RecurringSeries(
      id: id,
      label: newest.merchantName ?? (newest.descriptionText.isEmpty ? id : newest.descriptionText),
      amountMinor: medianAmount,
      occurrences: rows.count,
      lastDate: newest.date,
      nextExpected: nextExpected
    )
  }

  /// Even counts take the mean of the two central values, truncated. Both
  /// callers pass small non-negative integers — minor units and whole days — so
  /// the truncation costs at most one paisa or one day, and never a sign.
  private static func median(of values: [Int]) -> Int {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    guard sorted.count.isMultiple(of: 2) else { return sorted[middle] }
    return (sorted[middle - 1] + sorted[middle]) / 2
  }
}
