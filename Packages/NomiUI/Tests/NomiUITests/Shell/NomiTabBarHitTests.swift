import Testing
@testable import NomiUI

// clt-harness: include

/// I-16 Amendment 1 (F3c). `NomiTabBarHit` maps a touch's x to a slot for the UIKit
/// overlay, so the same geometry as `NomiTabBarMetrics` decides every selection. Pure.
@Suite("Tab bar hit slots")
struct NomiTabBarHitTests {
  @Test("slot centres are 34, 154 and 274 pt for slots 0, 2 and 4")
  func centres() {
    #expect(NomiTabBarHit.centreX(of: 0) == 34)
    #expect(NomiTabBarHit.centreX(of: 2) == 154)
    #expect(NomiTabBarHit.centreX(of: 4) == 274)
  }

  @Test("the centre of each slot maps to that slot")
  func slotAtEachCentre() {
    for index in 0..<5 {
      #expect(NomiTabBarHit.slot(atX: NomiTabBarHit.centreX(of: index)) == index)
    }
  }

  @Test("the middle of the first gap ties to the lower slot")
  func gapTieGoesLower() {
    // 7 pt padding + 54 pt circle + 3 pt: the midpoint of the 6 pt gap between slots 0 and 1.
    #expect(NomiTabBarHit.slot(atX: 7 + 54 + 3) == 0)
  }

  @Test("just past the first gap's midpoint maps to the next slot")
  func justPastGapGoesHigher() {
    #expect(NomiTabBarHit.slot(atX: 7 + 54 + 4) == 1)
  }

  @Test("the left padding maps to the first slot")
  func leftPadding() {
    #expect(NomiTabBarHit.slot(atX: 0) == 0)
    #expect(NomiTabBarHit.slot(atX: 3) == 0)
  }

  @Test("the right padding maps to the last slot, including the bar's far edge")
  func rightPadding() {
    #expect(NomiTabBarHit.slot(atX: 305) == 4)
    #expect(NomiTabBarHit.slot(atX: 308) == 4)
  }

  @Test("a point outside the bar on either side is nil")
  func outsideIsNil() {
    #expect(NomiTabBarHit.slot(atX: -0.5) == nil)
    #expect(NomiTabBarHit.slot(atX: 308.5) == nil)
  }
}
