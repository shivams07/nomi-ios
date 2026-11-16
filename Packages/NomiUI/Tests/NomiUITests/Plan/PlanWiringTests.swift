import XCTest

/// Source scans for the Plan screen's view wiring, because a SwiftUI body is not
/// reachable from a unit test. Each one names the mutant it kills (Lim's survivors on
/// PR #221: M3 and M4).
final class PlanWiringTests: XCTestCase {
  private func planScreenSource() throws -> String {
    // This file is Packages/NomiUI/Tests/NomiUITests/Plan/<name>.swift.
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Plan
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent("NomiUI/Sources/NomiUI/Plan/PlanScreen.swift")
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// M3. The bar's label row sits on the ground sheet, not in the hero: the one call
  /// falls between the start of `sheet` and the start of `budgetsSection`.
  func testLabelRowIsCalledOnTheSheetNotTheHero() throws {
    let text = try planScreenSource()
    XCTAssertEqual(text.components(separatedBy: "labelRow(totals)").count - 1, 1, "one label row call")
    let sheetStart = try XCTUnwrap(text.range(of: "private var sheet: some View {")).lowerBound
    let budgetsStart = try XCTUnwrap(text.range(of: "private var budgetsSection")).lowerBound
    let call = try XCTUnwrap(text.range(of: "labelRow(totals)")).lowerBound
    XCTAssertLessThan(sheetStart, call, "the label row is called from the sheet")
    XCTAssertLessThan(call, budgetsStart, "the label row sits before the Budgets section")
  }

  /// M4. The tile grid's column count reads the live Dynamic Type size, not a literal.
  func testBudgetColumnsReadsTheLiveDynamicTypeSize() throws {
    let text = try planScreenSource()
    XCTAssertTrue(text.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
    XCTAssertTrue(
      text.contains("PlanLogic.budgetColumns(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)"),
      "the grid passes the live size to budgetColumns")
  }

  /// The tile name and the recurring row use the predicates the tests pin.
  func testTileNamesAndSwipesUseTheTestedRules() throws {
    let text = try planScreenSource()
    XCTAssertTrue(text.contains("PlanLogic.tileNameLineLimit(item.categoryName)"))
    XCTAssertTrue(text.contains("PlanLogic.recurringSwipeOutcome("))
  }
}
