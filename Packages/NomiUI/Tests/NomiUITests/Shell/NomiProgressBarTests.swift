import XCTest
@testable import NomiUI

final class NomiProgressBarTests: XCTestCase {
  func testClampingNeverExceedsFullTrackAtOrAboveOneHundredPercent() {
    for input in [0.0, 0.89, 0.90, 1.0, 1.4] {
      let bar = NomiProgressBar(fraction: input)
      XCTAssertLessThanOrEqual(bar.clampedForTesting, 1.0)
      XCTAssertGreaterThanOrEqual(bar.clampedForTesting, 0.0)
    }
  }

  func testOverBudgetThresholdIsNinetyPercent() {
    XCTAssertFalse(NomiProgressBar(fraction: 0.89).isOverBudgetForTesting)
    XCTAssertTrue(NomiProgressBar(fraction: 0.90).isOverBudgetForTesting)
    XCTAssertTrue(NomiProgressBar(fraction: 1.4).isOverBudgetForTesting)
  }
}
