import XCTest

/// The tab roots own their bottom reserve (D4). Each of the four main scroll views reads
/// `\.nomiTabBarReserve`. A source scan, because a SwiftUI body is not reachable from a
/// unit test: deleting the modifier from any one of them is caught here, by name.
final class TabRootReserveWiringTests: XCTestCase {

  private func source(_ relativePath: String) throws -> String {
    // This file is Packages/NomiUI/Tests/NomiUITests/Shell/<name>.swift.
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Shell
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent("NomiUI/Sources/NomiUI/\(relativePath)")
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func assertReservesTheBottom(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws {
    let text = try source(relativePath)
    XCTAssertTrue(
      text.contains(".contentMargins(.bottom, tabBarReserve, for: .scrollContent)"),
      "\(relativePath) must reserve the tab bar on its main scroll view (D4)",
      file: file, line: line)
    XCTAssertTrue(
      text.contains("@Environment(\\.nomiTabBarReserve) private var tabBarReserve"),
      "\(relativePath) must read \\.nomiTabBarReserve",
      file: file, line: line)
  }

  func testHomeHeroScaffoldReservesTheBottom() throws {
    try assertReservesTheBottom("Shell/NomiHeroScaffold.swift")
  }

  func testActivityLedgerReservesTheBottom() throws {
    try assertReservesTheBottom("Ledger/LedgerScreen.swift")
  }

  func testInsightsReportsReservesTheBottom() throws {
    try assertReservesTheBottom("Reports/ReportsScreen.swift")
  }

  func testPlanBudgetsReservesTheBottom() throws {
    try assertReservesTheBottom("Budgets/BudgetsScreen.swift")
  }
}
