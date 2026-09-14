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
  ///
  /// Two carry a category badge and the third does not, so the card and the
  /// Subscriptions screen preview both the category tile and the monogram
  /// fallback (UI refresh P2). The badges repeat the id, name, symbol and slot
  /// of two `PreviewData.categories` rows, spelled out rather than read from
  /// there: those are `@Model` instances, and this `nonisolated` constant must
  /// not reach into them.
  ///
  /// `nonisolated` because `init` names it as a default argument, and default
  /// arguments are evaluated at the call site rather than inside the actor.
  /// Without it the reference is a warning today and an error under the Swift 6
  /// language mode. Safe: `RecurringSeries` is `Sendable` and this is a `let`.
  nonisolated public static let sampleSeries: [RecurringSeries] = {
    let day: TimeInterval = 86_400
    let bills = CategoryBadge(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
      name: "Bills & Utilities",
      symbolName: "bolt",
      paletteSlot: 3
    )
    let shopping = CategoryBadge(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
      name: "Shopping",
      symbolName: "bag",
      paletteSlot: 1
    )
    return [
      RecurringSeries(
        id: "NETFLIX",
        label: "Netflix",
        amountMinor: 64900,
        occurrences: 6,
        lastDate: Date(timeIntervalSinceNow: -27 * day),
        nextExpected: Date(timeIntervalSinceNow: 3 * day),
        categoryID: bills.id,
        category: bills
      ),
      RecurringSeries(
        id: "SPOTIFY INDIA",
        label: "Spotify",
        amountMinor: 11900,
        occurrences: 4,
        lastDate: Date(timeIntervalSinceNow: -21 * day),
        nextExpected: Date(timeIntervalSinceNow: 9 * day),
        categoryID: shopping.id,
        category: shopping
      ),
      // No badge: the monogram path.
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
