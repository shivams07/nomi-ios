import Testing
@testable import NomiApp

/// The bar steps aside while the keyboard is up, so a focused Ledger search
/// field stays clear of it (fid-ledger-search, D2). Pure, so it runs under
/// `swift test` without a view.
@Suite("Tab bar keyboard visibility")
struct TabBarKeyboardVisibilityTests {

  @Test("tab root with the keyboard down shows the bar")
  func rootWithoutKeyboardShows() {
    #expect(TabBarVisibility.isVisible(pathCount: 0, keyboardVisible: false) == true)
  }

  @Test("tab root with the keyboard up hides the bar")
  func tabBarHiddenWhileKeyboardVisible() {
    #expect(TabBarVisibility.isVisible(pathCount: 0, keyboardVisible: true) == false)
  }

  @Test("a pushed screen hides the bar with or without the keyboard")
  func pushedScreenHidesEitherWay() {
    #expect(TabBarVisibility.isVisible(pathCount: 1, keyboardVisible: false) == false)
    #expect(TabBarVisibility.isVisible(pathCount: 1, keyboardVisible: true) == false)
  }

  @Test("the keyboard flag alone never shows a bar the path has hidden")
  func keyboardCannotShowAPushedBar() {
    #expect(TabBarVisibility.isVisible(pathCount: 2, keyboardVisible: false) == TabBarVisibility.isVisible(pathCount: 2))
  }
}
