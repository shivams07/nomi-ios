import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// S1b step 4. "Where it went": the top four categories by spend, the caption
/// under each tile (left of a budget, over a budget, or share of spending), and
/// where a tap goes.
final class CategoryGridCardTests: XCTestCase {
  private func slice(_ name: String, _ totalMinor: Int, share: Double = 0.1, id: UUID = UUID()) -> CategorySlice {
    CategorySlice(id: id, name: name, symbolName: "cart", paletteSlot: 1, totalMinor: totalMinor, share: share)
  }

  private func budget(for id: UUID, budgetMinor: Int, spentMinor: Int) -> BudgetProgress {
    BudgetProgress(
      id: id,
      categoryName: "Budgeted",
      symbolName: "cart",
      paletteSlot: 1,
      budgetMinor: budgetMinor,
      spentMinor: spentMinor,
      fraction: Double(spentMinor) / Double(budgetMinor),
      periodKey: "2026-11"
    )
  }

  // MARK: - Top four

  func testShowsTheFourLargestCategoriesBySpendLargestFirst() {
    let slices = [
      slice("Small", 100_00),
      slice("Rent", 18_000_00),
      slice("Groceries", 2_140_00),
      slice("Shopping", 4_959_00),
      slice("Fuel", 900_00),
      slice("Ride-hailing", 3_565_00),
    ]

    let tiles = CategoryGridLogic.tiles(slices: slices, budgets: [])

    XCTAssertEqual(tiles.map(\.name), ["Rent", "Shopping", "Ride-hailing", "Groceries"])
  }

  func testFewerThanFourCategoriesShowsWhatExists() {
    let tiles = CategoryGridLogic.tiles(slices: [slice("Rent", 18_000_00), slice("Fuel", 900_00)], budgets: [])
    XCTAssertEqual(tiles.map(\.name), ["Rent", "Fuel"])
  }

  func testNoCategoriesGivesNoTiles() {
    XCTAssertTrue(CategoryGridLogic.tiles(slices: [], budgets: []).isEmpty)
  }

  /// A category with no spend this period is not "where it went".
  func testZeroSpendCategoriesAreLeftOut() {
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Rent", 18_000_00), slice("Gifts", 0)], budgets: [])
    XCTAssertEqual(tiles.map(\.name), ["Rent"])
  }

  // MARK: - Caption

  /// A budgeted category reads what is left of the budget.
  func testBudgetedTileCaptionIsLeftOfBudget() {
    let id = UUID()
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Shopping", 4_959_00, id: id)],
      budgets: [budget(for: id, budgetMinor: 5_000_00, spentMinor: 4_959_00)]
    )

    XCTAssertEqual(tiles.first?.caption, "₹41.00 left of ₹5,000.00")
    XCTAssertEqual(tiles.first?.isOver, false)
    XCTAssertEqual(tiles.first?.budgetState, .close)
  }

  /// Over a budget reads the overspend in words, and is flagged for the error text.
  func testOverBudgetCaptionIsOverTheBudget() {
    let id = UUID()
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Ride-hailing", 3_565_00, id: id)],
      budgets: [budget(for: id, budgetMinor: 2_600_00, spentMinor: 3_565_00)]
    )

    XCTAssertEqual(tiles.first?.caption, "₹965.00 over ₹2,600.00")
    XCTAssertEqual(tiles.first?.isOver, true)
    XCTAssertEqual(tiles.first?.budgetState, .over)
  }

  /// Without a budget this month, the caption is the category's share of spending.
  func testUnbudgetedTileCaptionIsShareOfSpending() {
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Rent", 18_000_00, share: 0.51)], budgets: [])

    XCTAssertEqual(tiles.first?.caption, "51% of spending")
    XCTAssertNil(tiles.first?.budgetState)
    XCTAssertNil(tiles.first?.budget)
  }

  /// A budget is matched by category id, so a budget for another category never
  /// changes this tile.
  func testBudgetIsMatchedByCategoryID() {
    let rentID = UUID()
    let otherID = UUID()
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Rent", 18_000_00, share: 0.51, id: rentID)],
      budgets: [budget(for: otherID, budgetMinor: 1_000_00, spentMinor: 900_00)]
    )

    XCTAssertEqual(tiles.first?.caption, "51% of spending")
  }

  // MARK: - Routing

  func testTileOpensItsCategoryInActivity() {
    let id = UUID()
    let tiles = CategoryGridLogic.tiles(slices: [slice("Rent", 18_000_00, id: id)], budgets: [])
    XCTAssertEqual(tiles.first?.destination, .category(id))
  }

  /// The uncategorised slice is not a category id, so it opens the Uncategorized chip.
  func testUncategorisedTileOpensTheUncategorizedFilter() {
    let tiles = CategoryGridLogic.tiles(
      slices: [slice("Uncategorized", 1_150_00, id: NomiCore.Category.uncategorizedID)], budgets: [])
    XCTAssertEqual(tiles.first?.destination, .uncategorized)
  }
}
