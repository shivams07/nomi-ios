import CoreGraphics
import Testing
@testable import NomiUI

/// The first-run Ledger's band: the scroll container's height less the tab bar's
/// reserved space (fid-ledger-search, D15). Figures in points, on screen.
///
/// The reserve is the environment's `\.nomiTabBarReserve` (S2): the bottom margin a
/// tab root reserves, which clears the bar by 12 pt. On a Face ID phone that is the
/// bar's 68 pt, plus its 26 pt offset, plus the 12 pt clearance, less the 34 pt
/// safe area, which is 72 pt.
@Suite("Ledger first-run band")
struct LedgerFirstRunBandTests {

  /// The reserve a Face ID phone's tab root gets from `NomiTabBarReserve.margin`.
  private let reserve = NomiTabBarReserve.margin(barHeight: NomiTabBarMetrics.barHeight, safeAreaBottom: 34)

  // iPhone 18 Pro (402 x 874): the scroll container runs from 85 to the bottom
  // safe edge at 840, a 755 pt container. The reserve is 72, so the band is 683 and
  // ends at 768. The bar's top is at 780, so the band clears it by 12 pt.
  @Test("18 Pro: band clears the tab bar's top by 12 pt")
  func eighteenProBand() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: reserve) == 683)
  }

  // iPhone 18 Pro Max (440 x 956), computed from the same rule: container 837
  // (85 to 922), reserve 72, so the band is 765 and ends at 850, clear of the bar.
  @Test("Pro Max, computed: band clears the tab bar's top")
  func proMaxBand() {
    #expect(LedgerFirstRunBand.height(containerHeight: 837, tabBottomReserve: reserve) == 765)
  }

  @Test("the environment reserve on a Face ID phone is 72 pt")
  func reserveOnAFaceIDPhone() {
    #expect(NomiTabBarReserve.margin(barHeight: NomiTabBarMetrics.barHeight, safeAreaBottom: 34) == 72)
  }

  @Test("an unset reserve leaves the whole container")
  func unsetReserve() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: 0) == 755)
  }

  @Test("a reserve taller than the container gives an empty band, never negative")
  func reserveTallerThanContainer() {
    #expect(LedgerFirstRunBand.height(containerHeight: 60, tabBottomReserve: reserve) == 0)
  }

  @Test("a zero container gives an empty band")
  func zeroContainer() {
    #expect(LedgerFirstRunBand.height(containerHeight: 0, tabBottomReserve: reserve) == 0)
  }

  @Test("non-finite inputs give an empty band")
  func nonFinite() {
    #expect(LedgerFirstRunBand.height(containerHeight: .nan, tabBottomReserve: reserve) == 0)
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: .infinity) == 0)
  }

  @Test("a negative reserve is treated as none")
  func negativeReserve() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: -10) == 755)
  }

  @Test("a larger Dynamic Type reserve shrinks the band by the same amount")
  func largerReserveShrinks() {
    let base = LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: reserve)
    let larger = LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: reserve + 40)
    #expect(base - larger == 40)
  }
}
