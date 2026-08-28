import Foundation
import NomiCore
import XCTest
@testable import NomiUI

final class ReportsCategoryFoldTests: XCTestCase {
  private func slice(_ index: Int, totalMinor: Int) -> CategorySlice {
    CategorySlice(id: UUID(), name: "Category \(index)", paletteSlot: index % 7, totalMinor: totalMinor, share: 0.1)
  }

  func testSevenOrFewerSlicesPassThroughUnchanged() {
    let slices = (0..<7).map { slice($0, totalMinor: (7 - $0) * 100) }
    let folded = ReportsCategoryFold.foldToSevenSlots(slices)
    XCTAssertEqual(folded.count, 7)
    XCTAssertFalse(folded.contains { $0.name == "Other" })
  }

  func testEighthCategoryFoldsToOther() {
    let slices = (0..<8).map { slice($0, totalMinor: (8 - $0) * 100) }
    let folded = ReportsCategoryFold.foldToSevenSlots(slices)
    XCTAssertEqual(folded.count, 8)
    XCTAssertEqual(folded.last?.name, "Other")
  }

  func testOtherTotalIsSumOfOverflowSlices() {
    let slices = (0..<9).map { slice($0, totalMinor: (9 - $0) * 100) }
    let folded = ReportsCategoryFold.foldToSevenSlots(slices)
    let overflowTotal = slices.sorted { $0.totalMinor > $1.totalMinor }.dropFirst(7).reduce(0) { $0 + $1.totalMinor }
    XCTAssertEqual(folded.last?.totalMinor, overflowTotal)
  }

  func testOtherUsesOutOfRangePaletteSlot() {
    let slices = (0..<8).map { slice($0, totalMinor: (8 - $0) * 100) }
    let folded = ReportsCategoryFold.foldToSevenSlots(slices)
    XCTAssertEqual(folded.last?.paletteSlot, -1)
  }

  func testEmptyInputReturnsEmpty() {
    XCTAssertTrue(ReportsCategoryFold.foldToSevenSlots([]).isEmpty)
  }
}
