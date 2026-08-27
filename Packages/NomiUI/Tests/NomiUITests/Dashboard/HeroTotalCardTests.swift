import Foundation
import XCTest
@testable import NomiUI

final class HeroTotalCardTests: XCTestCase {
  func testDeltaIsNilWithNoPriorPeriod() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: nil))
  }

  func testDeltaIsNilWhenPriorIsZero() {
    XCTAssertNil(HeroDelta.compute(current: 1000, prior: 0))
  }

  func testDeltaFlagsIncreaseWhenCurrentExceedsPrior() {
    let delta = HeroDelta.compute(current: 1200, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.percent ?? 0, 0.2, accuracy: 0.0001)
  }

  func testDeltaFlagsDecreaseWhenCurrentIsBelowPrior() {
    let delta = HeroDelta.compute(current: 800, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, false)
    XCTAssertEqual(delta?.percent ?? 0, -0.2, accuracy: 0.0001)
  }

  func testDeltaEqualToPriorCountsAsIncrease() {
    let delta = HeroDelta.compute(current: 1000, prior: 1000)
    XCTAssertEqual(delta?.isIncrease, true)
    XCTAssertEqual(delta?.percent ?? -1, 0, accuracy: 0.0001)
  }

  func testPercentTextRoundsToWholeNumber() {
    XCTAssertEqual(HeroDelta.percentText(0.2), "20%")
    XCTAssertEqual(HeroDelta.percentText(-0.2), "20%")
    XCTAssertEqual(HeroDelta.percentText(0.005), "1%")
  }

  func testReduceMotionRendersFinalValueImmediately() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: true), 42_318_00)
  }

  func testMotionEnabledStartsFromZeroForCountUp() {
    XCTAssertEqual(HeroCountUp.initialDisplayValue(target: 42_318_00, reduceMotion: false), 0)
  }
}
