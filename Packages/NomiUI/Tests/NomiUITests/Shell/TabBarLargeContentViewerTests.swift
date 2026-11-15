import XCTest

/// I-16 Amendment 1 (PR #204, 2026-11-16). The tab bar's slots carry no SwiftUI large
/// content viewer: its gesture takes the touch from a hold of about 0.2 s, and lifting
/// selects nothing. Until F3c moves the viewer into UIKit, all five slots, the + included,
/// have none. A source scan, because the modifier is not visible in a rendered view.
final class TabBarLargeContentViewerTests: XCTestCase {

  func testNoTabBarSlotCarriesTheSwiftUILargeContentViewer() throws {
    // This file is Packages/NomiUI/Tests/NomiUITests/Shell/<name>.swift.
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Shell
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent("NomiUI/Sources/NomiUI/Shell/NomiTabBar.swift")
    let text = try String(contentsOf: url, encoding: .utf8)
    XCTAssertFalse(
      text.contains("accessibilityShowsLargeContentViewer"),
      "NomiTabBar must not use the SwiftUI large content viewer (I-16 Amendment 1); F3c adds the UIKit one")
  }
}
