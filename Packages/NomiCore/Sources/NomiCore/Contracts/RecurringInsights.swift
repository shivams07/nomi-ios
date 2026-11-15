import Foundation

/// The read side of recurrence detection (U17a), and the whole of what the
/// "Upcoming" card (U17b) is allowed to know about it.
///
/// The detector is a heuristic over the ledger, and it stays one: a user cannot
/// confirm a series, edit its amount, or get a notification about it. The one
/// persisted user decision is dismissal (`dismiss(seriesID:)`, I-14): "not
/// recurring", which hides a series from `recurringSeries()`. It is stored in
/// `UserDefaults` and lives on this device only, so it needs no schema change
/// and does not sync; a second device shows the series again. There is no
/// un-dismiss, no snooze and no undo. If confirmation ever lands, it lands as
/// new methods here rather than as a second protocol.
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
  ///
  /// Series dismissed on this device are absent from this result, immediately
  /// and after a new store instance.
  func recurringSeries() throws -> [RecurringSeries]

  /// Hides series `id` (RecurringSeries.id, the normalized description) from
  /// recurringSeries() on this device. Dismissing an id that no series has is
  /// stored and harmless.
  func dismiss(seriesID: String) throws

  /// Ids dismissed on this device. For an "Undo" toast and tests.
  func dismissedSeriesIDs() -> Set<String>
}

/// Stub defaults for the two dismissal requirements, so a conformer that never
/// persists anything still compiles (`NoopRecurringStore` in the NomiUI tests).
/// The real conformers override both.
extension RecurringInsightsStore {
  public func dismiss(seriesID: String) throws {}

  public func dismissedSeriesIDs() -> Set<String> { [] }
}
