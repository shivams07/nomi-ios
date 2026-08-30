import XCTest

@testable import NomiUI

final class BackfillLifecycleTests: XCTestCase {

  func testAppearingForTheFirstTimeStarts() {
    XCTAssertTrue(BackfillLifecycle.shouldStartOnAppear(phase: .notStarted))
  }

  // The regression `onDisappear`'s cancel was covering for: without it, a
  // still-running scan must not be started a second time just because the
  // screen was left and come back to with no Cancel tap in between.
  func testLeavingMidScanAndReturningWithNoCancelDoesNotRestart() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .running))
  }

  func testReturningToACancelledScanDoesNotAutoResume() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .cancelled))
  }

  func testReturningToACompletedScanDoesNotRestart() {
    XCTAssertFalse(BackfillLifecycle.shouldStartOnAppear(phase: .completed))
  }
}
