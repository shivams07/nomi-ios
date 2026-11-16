import XCTest

@testable import NomiUI

/// The Plan bar's labels (S7). They sit on the ground sheet under the hero, in
/// moss900, which clears 4.5:1 there. The hero band they left is pinned as failing,
/// so the row cannot drift back onto the gradient without a red test.
final class PlanLabelRowContrastTests: XCTestCase {
  /// The label row on the ground sheet, moss900 text on `ground`.
  func testLabelRowTextPassesOnGround() {
    XCTAssertGreaterThanOrEqual(NomiContrast.ratio(NomiHex.navyDeep, NomiHex.ground), 4.5)
  }

  /// Measured in the test host at Large on a 62 pt safe top: the label row was at
  /// y 287.3 to 309.3 on a 345.3 pt hero. At that position the hero gradient fails
  /// both colours, so the labels cannot stay on the hero at Large. AX3 is lower
  /// still (y 351 to 459 on a 495 pt hero).
  func testTheOldHeroBandFailsBothColoursAtLarge() {
    let height: CGFloat = 345.33
    let safeTop: CGFloat = 62
    let background = gradientHex(atY: 309.33, height: height, safeTop: safeTop)
    XCTAssertLessThan(NomiContrast.ratio(NomiHex.white, background), 4.5)
    XCTAssertLessThan(NomiContrast.ratio(NomiHex.navyDeep, background), 4.5)
  }

  /// The colour the hero draws at `y`, from the same stops the hero uses. Each stop
  /// is a fraction of the height, so the colour is interpolated between the two
  /// stops that bracket `y / height`.
  private func gradientHex(atY y: CGFloat, height: CGFloat, safeTop: CGFloat) -> UInt32 {
    let stops = NomiHeroGradient.stops(height: height, safeTop: safeTop)
    let location = Double(y / height)
    guard let upper = stops.first(where: { $0.location >= location }) else { return stops[stops.count - 1].hex }
    guard let lower = stops.last(where: { $0.location <= location }), lower.location < upper.location else {
      return upper.hex
    }
    let t = (location - lower.location) / (upper.location - lower.location)
    var result: UInt32 = 0
    for shift in [16, 8, 0] as [UInt32] {
      let a = Double((lower.hex >> shift) & 0xFF)
      let b = Double((upper.hex >> shift) & 0xFF)
      result |= UInt32((a + (b - a) * t).rounded()) << shift
    }
    return result
  }
}
