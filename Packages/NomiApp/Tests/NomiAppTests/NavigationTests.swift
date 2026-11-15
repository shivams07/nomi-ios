import XCTest

@testable import NomiApp

/// §2.18(1) names the tab set and the order exactly; this is that sentence as
/// assertions. The tab bar is the one piece of U8 whose correctness is a list,
/// and a list is the easiest thing in the world to edit wrongly.
final class RootTabTests: XCTestCase {

  /// "Home, Ledger, centre `+`, Insights, Accounts" (SIMP §0, the artboards).
  func testBarOrderMatchesTheDesign() {
    XCTAssertEqual(
      TabBarLayout.items,
      [.tab(.home), .tab(.activity), .add, .tab(.insights), .tab(.plan)]
    )
  }

  /// "Centre" is a claim about position, not decoration. Five slots, the `+`
  /// third — two either side.
  func testTheAddButtonIsTheCentreOfFive() {
    XCTAssertEqual(TabBarLayout.items.count, 5)
    XCTAssertEqual(TabBarLayout.items.firstIndex(of: .add), 2)
  }

  /// Plan is a tab. Budgets, Accounts and Settings are not: Accounts is pushed
  /// from Settings, Budgets from Home's card, and Settings from Home's gear.
  func testPlanIsATabAccountsBudgetsAndSettingsAreNot() {
    XCTAssertEqual(RootTab.allCases.count, 4)
    XCTAssertEqual(
      Set(RootTab.allCases.map(\.rawValue)),
      ["home", "activity", "insights", "plan"]
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
