import NomiUI

/// G1. What a Needs-you tap asks the Activity tab to open on (F3b, I-15). Pure, so
/// the pairing is asserted without rendering `RootView`, whose destination closures
/// are private and whose `@Query` needs a container. `RootView` builds its two
/// Needs-you taps from `taps(open:)`.
enum NeedsYouRoute {
  /// The review card's tap: To review, because the card's review count is the
  /// queue's count.
  static let reviewQueue: ActivityRequest = .toReview

  /// The card's tap when its only count is uncategorized rows. To review is
  /// empty in that state, so this opens Uncategorized instead.
  static let uncategorized: ActivityRequest = .uncategorized

  /// The two taps `DashboardView` takes, each one running `open` with its
  /// request. Building them here keeps the handler-to-request pairing in one
  /// tested place rather than in `RootView`'s argument list.
  struct Taps {
    let reviewQueue: () -> Void
    let uncategorized: () -> Void
  }

  static func taps(open: @escaping (ActivityRequest) -> Void) -> Taps {
    Taps(
      reviewQueue: { apply(reviewQueue, request: open) },
      uncategorized: { apply(uncategorized, request: open) }
    )
  }

  /// Hands a tap's request to the Activity writer. `RootView` passes the same
  /// writer Home's See all uses, so both controls open the tab one way.
  static func apply(_ outcome: ActivityRequest, request: (ActivityRequest) -> Void) {
    request(outcome)
  }
}
