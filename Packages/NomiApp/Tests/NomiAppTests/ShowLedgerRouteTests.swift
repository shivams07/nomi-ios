// clt-harness: include
import Testing
@testable import NomiApp

/// FU-1's routing decision as assertions: "See all" and Import's "View in
/// Ledger" both select the Ledger tab and clear Home's stack. Swift-testing, so
/// it also runs in the CLT harness.
@Suite("Show Ledger route")
struct ShowLedgerRouteTests {

  @Test("the control selects the Ledger tab")
  func selectsLedger() {
    #expect(ShowLedgerRoute.outcome().selection == .ledger)
  }

  @Test("the target is a tab in the bar, and not Home")
  func targetIsABarTab() {
    let target = ShowLedgerRoute.outcome().selection
    #expect(target != .home)
    #expect(TabBarLayout.items.contains(.tab(target)))
  }

  @Test("Home's stack is cleared, so no pushed screen stays over the Ledger")
  func clearsHomeStack() {
    #expect(ShowLedgerRoute.outcome().clearsHomeStack)
  }
}
