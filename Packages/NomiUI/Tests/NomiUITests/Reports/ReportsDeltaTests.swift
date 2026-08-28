import XCTest
@testable import NomiUI

final class ReportsDeltaTests: XCTestCase {
  func testNilPriorReturnsNoResult() {
    XCTAssertNil(ReportsDelta.compute(current: 1000, prior: nil))
  }

  func testZeroPriorReturnsNoResultRatherThanInfinitePercent() {
    XCTAssertNil(ReportsDelta.compute(current: 1000, prior: 0))
  }

  func testIncreaseIsFlaggedWhenCurrentIsHigher() {
    let result = ReportsDelta.compute(current: 1200, prior: 1000)
    XCTAssertEqual(result?.isIncrease, true)
    XCTAssertEqual(result?.percent, 0.2, accuracy: 0.0001)
  }

  func testDecreaseIsFlaggedWhenCurrentIsLower() {
    let result = ReportsDelta.compute(current: 800, prior: 1000)
    XCTAssertEqual(result?.isIncrease, false)
    XCTAssertEqual(result?.percent, -0.2, accuracy: 0.0001)
  }

  func testEqualCurrentAndPriorCountsAsIncrease() {
    let result = ReportsDelta.compute(current: 1000, prior: 1000)
    XCTAssertEqual(result?.isIncrease, true)
    XCTAssertEqual(result?.percent, 0, accuracy: 0.0001)
  }

  func testPercentTextRoundsAndDropsSign() {
    XCTAssertEqual(ReportsDelta.percentText(0.2), "20%")
    XCTAssertEqual(ReportsDelta.percentText(-0.2), "20%")
    XCTAssertEqual(ReportsDelta.percentText(0.005), "1%")
  }
}
