// clt-harness: include
import Testing
@testable import NomiApp

/// The five-slot bar as assertions (SIMP §0, "Tab bar"): Home, Ledger, the
/// centre `+`, Insights, Accounts. Swift-testing, so it also runs in the CLT
/// harness (V2) and not only under Xcode.
@Suite("Tab bar order")
struct TabBarOrderTests {

  @Test("bar order is Home, Ledger, add, Insights, Accounts")
  func barOrder() {
    #expect(
      TabBarLayout.items == [.tab(.home), .tab(.ledger), .add, .tab(.insights), .tab(.accounts)]
    )
  }

  @Test("add is index 2 of 5, the centre")
  func addIsCentre() {
    #expect(TabBarLayout.items.count == 5)
    #expect(TabBarLayout.items.firstIndex(of: .add) == 2)
  }

  @Test("four tabs, no Budgets or Settings slot")
  func fourTabs() {
    #expect(RootTab.allCases.count == 4)
    #expect(RootTab.allCases == [.home, .ledger, .insights, .accounts])
  }

  @Test("every tab has a non-empty title and symbol, and titles and symbols are unique")
  func titlesAndSymbolsAreUnique() {
    let titles = RootTab.allCases.map(\.title)
    let symbols = RootTab.allCases.map(\.symbolName)
    #expect(titles.allSatisfy { !$0.isEmpty })
    #expect(symbols.allSatisfy { !$0.isEmpty })
    #expect(Set(titles).count == titles.count)
    #expect(Set(symbols).count == symbols.count)
  }

  @Test("the tab titles are the artboard labels")
  func titlesMatchArtboards() {
    #expect(RootTab.allCases.map(\.title) == ["Home", "Ledger", "Insights", "Accounts"])
  }

  @Test("the bar is visible only on a tab root")
  func visibilityFollowsThePath() {
    #expect(TabBarVisibility.isVisible(pathCount: 0) == true)
    #expect(TabBarVisibility.isVisible(pathCount: 1) == false)
    #expect(TabBarVisibility.isVisible(pathCount: 3) == false)
  }

  @Test("bar item ids are unique")
  func barItemIDsAreUnique() {
    let ids = TabBarLayout.items.map(\.id)
    #expect(Set(ids).count == ids.count)
  }
}
