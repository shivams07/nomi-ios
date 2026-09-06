import Foundation
import NomiCore

/// In-memory `RecurringInsightsStore` for previews and UI tests (U17a).
///
/// The sample series are dated relative to `Date()` rather than fixed, so
/// `nextExpected` is always in the future and the card previews as a user would
/// actually see it. They are also already in `nextExpected` order, matching what
/// the real store guarantees — a preview that arrived pre-sorted by accident
/// would hide a card that forgot to sort.
@MainActor
public final class FakeRecurringStore: RecurringInsightsStore {
  private let series: [RecurringSeries]
  private let failure: Error?

  /// - Parameters:
  ///   - series: pass `[]` for the empty state.
  ///   - failure: thrown instead of returning. Exists so the card's error state
  ///     has something to preview; the six screens U5 touched all show one.
  public init(series: [RecurringSeries] = FakeRecurringStore.sampleSeries, failure: Error? = nil) {
    self.series = series
    self.failure = failure
  }

  public func recurringSeries() throws -> [RecurringSeries] {
    if let failure { throw failure }
    return series
  }

  /// Three subscriptions at the amounts and cadences the detector is tuned for.
  public static let sampleSeries: [RecurringSeries] = {
    let day: TimeInterval = 86_400
    return [
      RecurringSeries(
        id: "NETFLIX",
        label: "Netflix",
        amountMinor: 64900,
        occurrences: 6,
        lastDate: Date(timeIntervalSinceNow: -27 * day),
        nextExpected: Date(timeIntervalSinceNow: 3 * day)
      ),
      RecurringSeries(
        id: "SPOTIFY INDIA",
        label: "Spotify",
        amountMinor: 11900,
        occurrences: 4,
        lastDate: Date(timeIntervalSinceNow: -21 * day),
        nextExpected: Date(timeIntervalSinceNow: 9 * day)
      ),
      RecurringSeries(
        id: "CULT FIT MEMBERSHIP",
        label: "Cult.fit",
        amountMinor: 249900,
        occurrences: 3,
        lastDate: Date(timeIntervalSinceNow: -14 * day),
        nextExpected: Date(timeIntervalSinceNow: 16 * day)
      ),
    ]
  }()
}
