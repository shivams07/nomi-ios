import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class CategoryBreakdownFoldTests: XCTestCase {
  private func slice(_ index: Int, total: Int) -> CategorySlice {
    CategorySlice(id: UUID(), name: "Category \(index)", paletteSlot: index % 7, totalMinor: total, share: 0)
  }

  func testSevenOrFewerCategoriesPassThroughUnchanged() {
    let slices = (0..<7).map { slice($0, total: (7 - $0) * 100) }
    let folded = CategoryFold.foldToSevenSlots(slices)
    XCTAssertEqual(folded.count, 7)
    XCTAssertFalse(folded.contains { $0.name == "Other" })
  }

  func testEighthCategoryFoldsIntoASingleOtherSlice() {
    let slices = (0..<8).map { slice($0, total: (8 - $0) * 100) }
    let folded = CategoryFold.foldToSevenSlots(slices)
    XCTAssertEqual(folded.count, 8, "seven real slices plus exactly one Other slice")
    XCTAssertEqual(folded.filter { $0.name == "Other" }.count, 1)
  }

  func testOtherSliceSumsAllOverflowTotals() {
    // Ranks 1-7 keep 800...200; rank 8 (100) and rank 9 (50) fold into Other.
    let slices = [800, 700, 600, 500, 400, 300, 200, 100, 50].enumerated().map { index, total in
      slice(index, total: total)
    }
    let folded = CategoryFold.foldToSevenSlots(slices)
    let other = folded.first { $0.name == "Other" }
    XCTAssertEqual(other?.totalMinor, 150)
  }

  func testOtherSliceResolvesToTheNeutralGreyViaTheExistingResolver() {
    let slices = (0..<8).map { slice($0, total: (8 - $0) * 100) }
    let other = CategoryFold.foldToSevenSlots(slices).first { $0.name == "Other" }
    XCTAssertNotNil(other)
    XCTAssertEqual(paletteSlot(other!.paletteSlot), CategoryPalette.other)
  }

  func testFoldedSlicesStayOrderedByTotalDescending() {
    let slices = [200, 800, 100, 500, 400, 300, 600, 50, 700].enumerated().map { index, total in
      slice(index, total: total)
    }
    let folded = CategoryFold.foldToSevenSlots(slices)
    let totals = folded.map(\.totalMinor)
    XCTAssertEqual(totals, totals.sorted(by: >))
  }

  func testEmptyInputProducesEmptyOutput() {
    XCTAssertTrue(CategoryFold.foldToSevenSlots([]).isEmpty)
  }
}
