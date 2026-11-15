import XCTest

/// Three behaviours of the tab shell that a unit test cannot reach, pinned by a source
/// scan of `RootView.swift`. Each one kills a named mutant:
/// - M2: a reserve on the whole destination instead of on each tab root.
/// - M3: a hidden tab still hit-testable and visible to accessibility.
/// - M4: the Activity chip reset when the tab changes.
final class TabShellWiringTests: XCTestCase {

  private func rootView() throws -> String {
    // This file is Packages/NomiApp/Tests/NomiAppTests/<name>.swift.
    let package = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
    let url = package.appendingPathComponent("Sources/NomiApp/Navigation/RootView.swift")
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// M2. RootView never adds bottom margin to a destination. The four tab roots do it
  /// on their own scroll views, so a chip row above the content is not padded.
  func testRootViewReservesNoSpaceForAWholeDestination() throws {
    XCTAssertFalse(
      try rootView().contains(".contentMargins("),
      "RootView must not pad the destination; each tab root owns its reserve (D4)")
  }

  /// M3. A tab that is not selected is neither hit-testable nor shown to accessibility.
  func testHiddenTabsAreNotHitTestableOrAccessible() throws {
    let text = try rootView()
    XCTAssertTrue(
      text.contains(".allowsHitTesting(tab == selection)"),
      "a hidden tab must not take taps")
    XCTAssertTrue(
      text.contains(".accessibilityHidden(tab != selection)"),
      "a hidden tab must not be read by VoiceOver")
  }

  /// M4. The Activity request is written only by `showActivity`, so switching tabs never
  /// resets the chip a screen was opened on, and nothing watches `selection` to clear it.
  func testOnlyShowActivityWritesTheActivityRequest() throws {
    let text = try rootView()
    let writes = text.components(separatedBy: "\n").filter { $0.contains("activityRequest = ") }
    XCTAssertEqual(writes.count, 1, "activityRequest must be written in exactly one place: \(writes)")
    XCTAssertFalse(
      text.contains(".onChange(of: selection)"),
      "no handler on tab change may reset the Activity request (Y4)")
  }
}
