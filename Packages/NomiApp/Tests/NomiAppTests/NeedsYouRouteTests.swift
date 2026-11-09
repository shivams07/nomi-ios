import NomiUI
import XCTest

@testable import NomiApp

/// G1 (WR-3b). `RootView`'s Needs-you taps are built by `NeedsYouRoute.taps`,
/// and each one writes an outcome through `NeedsYouRoute.apply`. These tests run
/// the taps the way `RootView` runs them, with a recording sink in place of the
/// state, so a change to which chip a tap opens, or to the order the chip and
/// the tab are written, fails here by name.
final class NeedsYouRouteTests: XCTestCase {

  // MARK: - The outcome each handler opens

  func testReviewQueueOpensTheNeedsReviewChipOnTheLedger() {
    XCTAssertEqual(
      NeedsYouRoute.reviewQueue,
      NeedsYouRoute.Outcome(initialChip: .needsReview, selection: .ledger))
  }

  /// The regression R1 names: the uncategorized card routed to Needs review.
  func testUncategorizedOpensTheUncategorizedChipNotNeedsReview() {
    XCTAssertEqual(
      NeedsYouRoute.uncategorized,
      NeedsYouRoute.Outcome(initialChip: .uncategorized, selection: .ledger))
    XCTAssertNotEqual(NeedsYouRoute.uncategorized.initialChip, .needsReview)
  }

  // MARK: - Through the taps RootView passes to DashboardView

  func testUncategorizedTapWritesTheUncategorizedOutcome() {
    var written: [NeedsYouRoute.Outcome] = []
    let taps = NeedsYouRoute.taps { written.append($0) }

    taps.uncategorized()

    XCTAssertEqual(written, [NeedsYouRoute.uncategorized])
  }

  func testReviewQueueTapWritesTheReviewOutcome() {
    var written: [NeedsYouRoute.Outcome] = []
    let taps = NeedsYouRoute.taps { written.append($0) }

    taps.reviewQueue()

    XCTAssertEqual(written, [NeedsYouRoute.reviewQueue])
  }

  /// Each tap writes exactly one outcome and nothing until it is run, so a
  /// card that is only built does not move the Ledger.
  func testBuildingTheTapsWritesNothing() {
    var written: [NeedsYouRoute.Outcome] = []
    _ = NeedsYouRoute.taps { written.append($0) }

    XCTAssertTrue(written.isEmpty)
  }

  // MARK: - The order RootView writes the state in

  /// `LedgerScreen` reads `initialChip` once, when the tab moves to `.ledger`
  /// constructs it. The chip has to be written first, so this records the
  /// writes in order.
  func testChipIsWrittenBeforeTheTabMovesToTheLedger() {
    var writes: [String] = []

    NeedsYouRoute.apply(
      NeedsYouRoute.uncategorized,
      setChip: { writes.append("chip:\($0)") },
      setSelection: { writes.append("tab:\($0.rawValue)") }
    )

    XCTAssertEqual(writes, ["chip:uncategorized", "tab:ledger"])
  }

  func testReviewChipIsWrittenBeforeTheTabMovesToTheLedger() {
    var writes: [String] = []

    NeedsYouRoute.apply(
      NeedsYouRoute.reviewQueue,
      setChip: { writes.append("chip:\($0)") },
      setSelection: { writes.append("tab:\($0.rawValue)") }
    )

    XCTAssertEqual(writes, ["chip:needsReview", "tab:ledger"])
  }

  /// The end-to-end path a tap takes into `RootView`'s state: the tap, then the
  /// writer `RootView` hands `taps(open:)`, then `apply`. Both halves at once.
  func testUncategorizedTapEndsWithTheUncategorizedChipAndTheLedgerTab() {
    var chip: LedgerChipSelection = .all
    var tab: RootTab = .home
    let taps = NeedsYouRoute.taps { outcome in
      NeedsYouRoute.apply(outcome, setChip: { chip = $0 }, setSelection: { tab = $0 })
    }

    taps.uncategorized()

    XCTAssertEqual(chip, .uncategorized)
    XCTAssertEqual(tab, .ledger)
  }
}
