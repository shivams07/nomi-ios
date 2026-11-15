import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// F3a's bar geometry, pinned as values (I-16). The bar draws icons only, so none of
/// these depend on Dynamic Type: the bar is the same size at every size.
@Suite("Tab bar metrics")
struct NomiTabBarSizingTests {
  @Test("every circle is 54 pt, the + included")
  func slotIs54() {
    #expect(NomiTabBarMetrics.slot == 54)
  }

  @Test("neighbouring circles are 6 pt apart")
  func gapIs6() {
    #expect(NomiTabBarMetrics.gap == 6)
  }

  @Test("the capsule pads its circles by 7 pt on every side")
  func paddingIs7() {
    #expect(NomiTabBarMetrics.padding == 7)
  }

  @Test("the bar is 68 pt high: one circle plus the padding above and below")
  func barHeightIs68() {
    #expect(NomiTabBarMetrics.barHeight == 68)
    #expect(NomiTabBarMetrics.barHeight == NomiTabBarMetrics.slot + 2 * NomiTabBarMetrics.padding)
  }

  @Test("the bar is 308 pt wide: five circles, four gaps and the two paddings")
  func barWidthIs308() {
    #expect(NomiTabBarMetrics.barWidth == 5 * NomiTabBarMetrics.slot + 4 * NomiTabBarMetrics.gap + 2 * NomiTabBarMetrics.padding)
    #expect(NomiTabBarMetrics.barWidth == 308)
  }

  @Test("the bar sits 26 pt above the physical bottom edge")
  func bottomOffsetIs26() {
    #expect(NomiTabBarMetrics.bottomOffset == 26)
  }
}
