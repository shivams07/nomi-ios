import XCTest

@testable import NomiApp

/// §2.18(1) names the tab set and the order exactly; this is that sentence as
/// assertions. The tab bar is the one piece of U8 whose correctness is a list,
/// and a list is the easiest thing in the world to edit wrongly.
final class RootTabTests: XCTestCase {

  /// "Tabs: Dashboard, Ledger, centre `+`, Reports, Settings."
  func testBarOrderMatchesTheDesign() {
    XCTAssertEqual(
      TabBarLayout.items,
      [.tab(.dashboard), .tab(.ledger), .add, .tab(.reports), .tab(.settings)]
    )
  }

  /// "Centre" is a claim about position, not decoration. Five slots, the `+`
  /// third — two either side.
  func testTheAddButtonIsTheCentreOfFive() {
    XCTAssertEqual(TabBarLayout.items.count, 5)
    XCTAssertEqual(TabBarLayout.items.firstIndex(of: .add), 2)
  }

  /// "Accounts and Budgets hang off Dashboard/Settings, not off the bar."
  /// `RootView` pushes them from those two tabs' toolbars.
  func testAccountsAndBudgetsAreNotTabs() {
    XCTAssertEqual(RootTab.allCases.count, 4)
    XCTAssertEqual(
      Set(RootTab.allCases.map(\.rawValue)),
      ["dashboard", "ledger", "reports", "settings"]
    )
  }

  /// The `+` presents the entry sheet and selects nothing, so it must not be
  /// expressible as a selection — otherwise every `switch` over the destination
  /// carries a branch that cannot happen.
  func testEverySelectableTabHasADestination() {
    for tab in RootTab.allCases {
      XCTAssertFalse(tab.title.isEmpty)
      XCTAssertFalse(tab.symbolName.isEmpty)
    }
  }

  func testBarItemIDsAreUnique() {
    XCTAssertEqual(Set(TabBarLayout.items.map(\.id)).count, TabBarLayout.items.count)
  }
}
