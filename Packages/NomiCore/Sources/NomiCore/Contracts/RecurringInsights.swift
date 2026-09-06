import Foundation

/// The read side of recurrence detection (U17a), and the whole of what the
/// "Upcoming" card (U17b) is allowed to know about it.
///
/// Deliberately one method. The detector is a heuristic over the ledger, not a
/// user-editable list: there is no confirm, no deny, no snooze and no
/// notification, because every one of those needs persisted state and a
/// migration, and none of them is what U17 asked for. A store that answers
/// "what looks like it repeats" is the entire contract; if confirmation ever
/// lands, it lands as new methods here rather than as a second protocol.
///
/// `@MainActor`, like every other store in `Stores.swift`, and for the same
/// reason: the real implementation reads a `ModelContext` that is bound to the
/// main actor, and the screens that call it are already there.
@MainActor
public protocol RecurringInsightsStore: AnyObject {
  /// Series detected in the store's own recent window, ordered by
  /// `nextExpected` — soonest first.
  ///
  /// **The order is part of the contract**, not an accident of how the rows
  /// came back. The implementation groups into a dictionary, whose iteration
  /// order varies run to run; a caller that took that order and showed the
  /// first five would show a different five on each render. `RecurrenceDetector`
  /// sorts before returning, so a caller may rely on this and does not have to
  /// re-sort defensively.
  func recurringSeries() throws -> [RecurringSeries]
}
