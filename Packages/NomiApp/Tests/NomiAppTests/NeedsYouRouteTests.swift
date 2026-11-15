import NomiUI
import XCTest

@testable import NomiApp

/// G1 (WR-3b). `RootView`'s Needs-you taps are built by `NeedsYouRoute.taps`,
/// and each one hands its request to `NeedsYouRoute.apply`, which passes it on
/// to the Activity writer. These tests run the taps the way `RootView` runs
/// them, so a change to which request a tap opens fails here by name.
final class NeedsYouRouteTests: XCTestCase {

  // MARK: - The request each handler opens

  func testReviewQueueOpensToReview() {
    XCTAssertEqual(NeedsYouRoute.reviewQueue, .toReview)
  }

  /// The regression R1 names: the uncategorized card routed to Needs review.
  func testUncategorizedOpensUncategorizedNotToReview() {
    XCTAssertEqual(NeedsYouRoute.uncategorized, .uncategorized)
    XCTAssertNotEqual(NeedsYouRoute.uncategorized, .toReview)
  }

  // MARK: - Through the taps RootView passes to DashboardView

  func testUncategorizedTapWritesTheUncategorizedRequest() {
    var written: [ActivityRequest] = []
    let taps = NeedsYouRoute.taps { written.append($0) }

    taps.uncategorized()

    XCTAssertEqual(written, [.uncategorized])
  }

  func testReviewQueueTapWritesTheToReviewRequest() {
    var written: [ActivityRequest] = []
    let taps = NeedsYouRoute.taps { written.append($0) }

    taps.reviewQueue()

    XCTAssertEqual(written, [.toReview])
  }

  /// Each tap writes exactly one request and nothing until it is run, so a
  /// card that is only built does not move the Activity tab.
  func testBuildingTheTapsWritesNothing() {
    var written: [ActivityRequest] = []
    _ = NeedsYouRoute.taps { written.append($0) }

    XCTAssertTrue(written.isEmpty)
  }

  /// `apply` hands the request to the writer unchanged, so the one function
  /// `RootView` calls for Needs-you is the same one Home's See all goes through.
  func testApplyPassesTheRequestThrough() {
    var received: [ActivityRequest] = []

    NeedsYouRoute.apply(.uncategorized, request: { received.append($0) })

    XCTAssertEqual(received, [.uncategorized])
  }

  /// The end-to-end path a tap takes: the tap, the writer `RootView` hands
  /// `taps(open:)`, then `apply`.
  func testUncategorizedTapEndsAtTheUncategorizedRequest() {
    var shown: ActivityRequest?
    let taps = NeedsYouRoute.taps { request in
      NeedsYouRoute.apply(request, request: { shown = $0 })
    }

    taps.uncategorized()

    XCTAssertEqual(shown, .uncategorized)
  }

  // MARK: - The request becomes the Activity chip

  func testToReviewRequestOpensTheNeedsReviewChip() {
    XCTAssertEqual(ActivityRoute.chip(for: .toReview), .needsReview)
  }

  func testUncategorizedRequestOpensTheUncategorizedChip() {
    XCTAssertEqual(ActivityRoute.chip(for: .uncategorized), .uncategorized)
  }

  func testCategoryRequestOpensThatCategoryChip() {
    let id = UUID()
    XCTAssertEqual(ActivityRoute.chip(for: .category(id)), .category(id))
  }

  func testAllAndSearchRequestsOpenTheAllChip() {
    XCTAssertEqual(ActivityRoute.chip(for: .all), .all)
    XCTAssertEqual(ActivityRoute.chip(for: .search("swiggy")), .all)
  }
}
