import XCTest
@testable import NomiUI

final class NomiRingGaugeTests: XCTestCase {
  func testClampingNeverExceedsFullRingAtOrAboveOneHundredPercent() {
    for input in [0.0, 0.89, 0.90, 1.0, 1.4] {
      let gauge = NomiRingGauge(fraction: input)
      XCTAssertLessThanOrEqual(gauge.clampedForTesting, 1.0)
      XCTAssertGreaterThanOrEqual(gauge.clampedForTesting, 0.0)
    }
  }

  func testOverBudgetThresholdIsNinetyPercent() {
    XCTAssertFalse(NomiRingGauge(fraction: 0.89).isOverBudgetForTesting)
    XCTAssertTrue(NomiRingGauge(fraction: 0.90).isOverBudgetForTesting)
    XCTAssertTrue(NomiRingGauge(fraction: 1.4).isOverBudgetForTesting)
  }
}
