import CoreGraphics
import Testing
@testable import NomiUI

/// The first-run Ledger's band: the scroll container's height less the tab bar's
/// reserved space (fid-ledger-search, D15). Figures in points, on screen.
@Suite("Ledger first-run band")
struct LedgerFirstRunBandTests {

  // iPhone 18 Pro (402 x 874): the scroll container runs from 85 to the bottom
  // safe edge at 840, a 755 pt container. The bar reserves 94 pt (68 bar + 26
  // offset), so the band is 661 and ends at 746, which clears the bar's top (780).
  @Test("18 Pro: band clears the tab bar's top")
  func eighteenProBand() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: LedgerFirstRunBand.tabBarReserve) == 661)
  }

  // iPhone 18 Pro Max (440 x 956), computed from the same rule: container 837
  // (85 to 922), reserve 94, so the band is 743 and ends at 828, clear of the bar.
  @Test("Pro Max, computed: band clears the tab bar's top")
  func proMaxBand() {
    #expect(LedgerFirstRunBand.height(containerHeight: 837, tabBottomReserve: LedgerFirstRunBand.tabBarReserve) == 743)
  }

  @Test("the reserve is the bar's height plus its offset, 94 pt")
  func reserveIsBarPlusOffset() {
    #expect(LedgerFirstRunBand.tabBarReserve == 94)
  }

  @Test("an unset reserve leaves the whole container")
  func unsetReserve() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: 0) == 755)
  }

  @Test("a reserve taller than the container gives an empty band, never negative")
  func reserveTallerThanContainer() {
    #expect(LedgerFirstRunBand.height(containerHeight: 60, tabBottomReserve: LedgerFirstRunBand.tabBarReserve) == 0)
  }

  @Test("a zero container gives an empty band")
  func zeroContainer() {
    #expect(LedgerFirstRunBand.height(containerHeight: 0, tabBottomReserve: LedgerFirstRunBand.tabBarReserve) == 0)
  }

  @Test("non-finite inputs give an empty band")
  func nonFinite() {
    #expect(LedgerFirstRunBand.height(containerHeight: .nan, tabBottomReserve: LedgerFirstRunBand.tabBarReserve) == 0)
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: .infinity) == 0)
  }

  @Test("a negative reserve is treated as none")
  func negativeReserve() {
    #expect(LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: -10) == 755)
  }

  @Test("a larger Dynamic Type reserve shrinks the band by the same amount")
  func largerReserveShrinks() {
    let base = LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: LedgerFirstRunBand.tabBarReserve)
    let larger = LedgerFirstRunBand.height(containerHeight: 755, tabBottomReserve: LedgerFirstRunBand.tabBarReserve + 40)
    #expect(base - larger == 40)
  }
}
