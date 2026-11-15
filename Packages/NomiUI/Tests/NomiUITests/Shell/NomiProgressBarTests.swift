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

  /// The one-argument init keeps every existing caller compiling and maps the
  /// fraction onto the three budget states: under below 90%, close from 90%,
  /// over from 100%.
  func testOneArgumentInitMapsFractionToBudgetState() {
    XCTAssertEqual(NomiProgressBar(fraction: 0.89).state, .under)
    XCTAssertEqual(NomiProgressBar(fraction: 0.90).state, .close)
    XCTAssertEqual(NomiProgressBar(fraction: 1.0).state, .over)
    XCTAssertEqual(NomiProgressBar(fraction: 1.4).state, .over)
  }

  func testFillFollowsTheStateTokens() {
    XCTAssertEqual(NomiProgressBar(fraction: 0.5, state: .under).fillHexForTesting, NomiHex.navy)
    XCTAssertEqual(NomiProgressBar(fraction: 0.95, state: .close).fillHexForTesting, NomiHex.warningFill)
    XCTAssertEqual(NomiProgressBar(fraction: 1.1, state: .over).fillHexForTesting, NomiHex.error)
  }

  /// On a hero the state is ignored: the track is white at 30% and the fill is white.
  func testOnHeroIgnoresStateAndUsesWhite() {
    let bar = NomiProgressBar(fraction: 1.2, state: .over, onHero: true)
    XCTAssertEqual(bar.fillHexForTesting, NomiHex.white)
  }
}
