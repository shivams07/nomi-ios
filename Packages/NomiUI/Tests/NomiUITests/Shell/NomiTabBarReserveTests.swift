import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// F3b's bottom reserve, as a pure rule: a tab root's main scroll view adds this
/// much bottom margin so its last row clears the floating bar by 12 pt. Swift
/// Testing, so the CLT harness runs it too.
@Suite("Tab bar reserve")
struct NomiTabBarReserveTests {
  @Test("on a phone with a 34 pt bottom safe area the reserve is 72 pt")
  func reserveWithHomeIndicator() {
    #expect(NomiTabBarReserve.margin(barHeight: 68, safeAreaBottom: 34) == 72)
  }

  @Test("with no bottom safe area the reserve is 106 pt: bar, offset and gap")
  func reserveWithoutSafeArea() {
    #expect(NomiTabBarReserve.margin(barHeight: 68, safeAreaBottom: 0) == 106)
  }

  @Test("the reserve is the bar height plus its offset plus the 12 pt gap, less the safe area")
  func reserveFollowsTheMetrics() {
    let expected = NomiTabBarMetrics.barHeight + NomiTabBarMetrics.bottomOffset + 12 - 34
    #expect(NomiTabBarReserve.margin(barHeight: NomiTabBarMetrics.barHeight, safeAreaBottom: 34) == expected)
  }

  @Test("the reserve is never negative, even when the safe area is larger than the bar")
  func reserveNeverNegative() {
    #expect(NomiTabBarReserve.margin(barHeight: 0, safeAreaBottom: 500) == 0)
    #expect(NomiTabBarReserve.margin(barHeight: 68, safeAreaBottom: 400) == 0)
  }

  @Test("the environment value defaults to zero, so nothing reserves space unless a tab root sets it")
  func environmentDefaultIsZero() {
    let values = EnvironmentValues()
    #expect(values.nomiTabBarReserve == 0)
  }
}
