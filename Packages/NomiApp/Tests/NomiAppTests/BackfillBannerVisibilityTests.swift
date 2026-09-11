import NomiCore
import XCTest

@testable import NomiApp

final class BackfillBannerVisibilityTests: XCTestCase {
  func testNoTickYetButUnfinishedShows() {
    XCTAssertTrue(BackfillBannerVisibility.shouldShow(progress: nil, unfinished: true))
  }

  func testIncompleteTickAndUnfinishedShows() {
    let progress = BackfillProgress(scanned: 50, total: 100, created: 5)
    XCTAssertTrue(BackfillBannerVisibility.shouldShow(progress: progress, unfinished: true))
  }

  func testCompleteTickAndUnfinishedHides() {
    let progress = BackfillProgress(scanned: 100, total: 100, created: 9)
    XCTAssertFalse(BackfillBannerVisibility.shouldShow(progress: progress, unfinished: true))
  }

  func testNotUnfinishedNeverShowsRegardlessOfProgress() {
    XCTAssertFalse(BackfillBannerVisibility.shouldShow(progress: nil, unfinished: false))
    XCTAssertFalse(
      BackfillBannerVisibility.shouldShow(
        progress: BackfillProgress(scanned: 50, total: 100, created: 5),
        unfinished: false
      )
    )
    XCTAssertFalse(
      BackfillBannerVisibility.shouldShow(
        progress: BackfillProgress(scanned: 100, total: 100, created: 9),
        unfinished: false
      )
    )
  }
}
