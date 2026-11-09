import NomiUI

/// G1. What a Needs-you tap does to the Ledger: the chip it opens on, and the
/// tab it selects. Pure, so the pairing is asserted without rendering
/// `RootView`, whose destination closures are private and whose `@Query` needs a
/// container. `RootView` builds its two Needs-you taps from `taps(open:)`.
enum NeedsYouRoute {
  /// What a tap writes into `RootView`'s state.
  struct Outcome: Equatable {
    let initialChip: LedgerChipSelection
    let selection: RootTab
  }

  /// The review card's tap: the Needs review chip, because the card's review
  /// count is the queue's count.
  static let reviewQueue = Outcome(initialChip: .needsReview, selection: .ledger)

  /// The card's tap when its only count is uncategorized rows. The Needs review
  /// chip is empty in that state, so this opens Uncategorized instead.
  static let uncategorized = Outcome(initialChip: .uncategorized, selection: .ledger)

  /// The two taps `DashboardView` takes, each one running `open` with its
  /// outcome. Building them here keeps the handler-to-outcome pairing in one
  /// tested place rather than in `RootView`'s argument list.
  struct Taps {
    let reviewQueue: () -> Void
    let uncategorized: () -> Void
  }

  static func taps(open: @escaping (Outcome) -> Void) -> Taps {
    Taps(
      reviewQueue: { open(NeedsYouRoute.reviewQueue) },
      uncategorized: { open(NeedsYouRoute.uncategorized) }
    )
  }

  /// Writes an outcome into `RootView`'s state, chip first. `LedgerScreen` reads
  /// `initialChip` once, when it is constructed, and the tab moving to `.ledger`
  /// is what constructs it, so the chip has to be in place before the tab moves.
  static func apply(
    _ outcome: Outcome,
    setChip: (LedgerChipSelection) -> Void,
    setSelection: (RootTab) -> Void
  ) {
    setChip(outcome.initialChip)
    setSelection(outcome.selection)
  }
}
