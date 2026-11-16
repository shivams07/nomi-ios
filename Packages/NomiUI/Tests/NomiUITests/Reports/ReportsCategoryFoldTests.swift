import Foundation
import NomiCore
import SwiftUI
import XCTest
@testable import NomiUI

final class ReportsCategoryFoldTests: XCTestCase {
  private func slice(_ index: Int, totalMinor: Int) -> CategorySlice {
    CategorySlice(id: UUID(), name: "Category \(index)", paletteSlot: index % 7, totalMinor: totalMinor, share: 0.1)
  }

  private func uncategorised(totalMinor: Int) -> CategorySlice {
    CategorySlice(id: NomiCore.Category.uncategorizedID, name: "Uncategorized", paletteSlot: 0, totalMinor: totalMinor, share: 0.1)
  }

  private var grey: Color {
    NomiColor.inkSecondary.opacity(0.3)
  }

  func testFourCategoriesGetRanksAndNoFoldedRow() {
    let breakdown = ReportsCategoryFold.breakdown((0..<4).map { slice($0, totalMinor: (4 - $0) * 100) })

    XCTAssertEqual(breakdown.rows.map(\.kind), [.category(rank: 0), .category(rank: 1), .category(rank: 2), .category(rank: 3)])
    XCTAssertEqual(breakdown.totalMinor, 1_000)
  }

  /// Fold count: the fifth and later categories become one row, counted.
  func testCategoriesBeyondTheFourthFoldIntoOneCountedRow() {
    let slices = (0..<6).map { slice($0, totalMinor: (6 - $0) * 100) }
    let breakdown = ReportsCategoryFold.breakdown(slices)

    XCTAssertEqual(breakdown.rows.last?.kind, .folded(count: 2))
    XCTAssertEqual(breakdown.rows.last?.totalMinor, 100 + 200)
    XCTAssertEqual(breakdown.rows.last?.id, ReportsCategoryFold.otherOverflowID)
    XCTAssertEqual(breakdown.rows.count, 5)
  }

  /// Uncategorised is always its own row, amber, and never ranked, whatever its size.
  func testUncategorisedIsItsOwnRowEvenWhenLargest() {
    let breakdown = ReportsCategoryFold.breakdown([
      uncategorised(totalMinor: 900),
      slice(0, totalMinor: 400),
      slice(1, totalMinor: 100),
    ])

    XCTAssertEqual(breakdown.rows.map(\.kind), [.category(rank: 0), .category(rank: 1), .uncategorised])
    XCTAssertEqual(breakdown.rows.last?.totalMinor, 900)
  }

  func testNoUncategorisedRowWhenNothingIsUncategorised() {
    let breakdown = ReportsCategoryFold.breakdown([slice(0, totalMinor: 100)])
    XCTAssertFalse(breakdown.rows.contains { $0.kind == .uncategorised })
  }

  func testZeroSpendSlicesAreSkipped() {
    let breakdown = ReportsCategoryFold.breakdown([slice(0, totalMinor: 0), slice(1, totalMinor: 500)])
    XCTAssertEqual(breakdown.rows.map(\.kind), [.category(rank: 0)])
    XCTAssertEqual(breakdown.totalMinor, 500)
  }

  func testEmptyInputGivesNoRows() {
    let breakdown = ReportsCategoryFold.breakdown([])
    XCTAssertTrue(breakdown.rows.isEmpty)
    XCTAssertEqual(breakdown.totalMinor, 0)
  }

  func testSharesSumToTheWholeAcrossRows() {
    let breakdown = ReportsCategoryFold.breakdown([
      slice(0, totalMinor: 300),
      slice(1, totalMinor: 100),
      uncategorised(totalMinor: 100),
    ])
    XCTAssertEqual(breakdown.rows.map(\.share).reduce(0, +), 1.0, accuracy: 0.0001)
  }

  /// Rank colours: m900, m700, m500, m300 for the top four.
  func testRankColoursAreTheMossScale() {
    XCTAssertEqual(ReportsCategoryFold.colour(rank: 0, isUncategorised: false), NomiColor.navyDeep)
    XCTAssertEqual(ReportsCategoryFold.colour(rank: 1, isUncategorised: false), NomiColor.navy)
    XCTAssertEqual(ReportsCategoryFold.colour(rank: 2, isUncategorised: false), NomiColor.blueMid)
    XCTAssertEqual(ReportsCategoryFold.colour(rank: 3, isUncategorised: false), NomiColor.chartTintMid)
  }

  /// Anything past the fourth rank is the folded grey.
  func testRanksBeyondTheFourthAreGrey() {
    XCTAssertEqual(ReportsCategoryFold.colour(rank: 4, isUncategorised: false), grey)
    XCTAssertEqual(ReportsCategoryFold.colour(for: .folded(count: 2)), grey)
  }

  /// Uncategorised is amber at every rank, so the rank can never recolour it.
  func testUncategorisedIsAlwaysAmber() {
    for rank in 0...5 {
      XCTAssertEqual(ReportsCategoryFold.colour(rank: rank, isUncategorised: true), NomiColor.warningFill)
    }
    XCTAssertEqual(ReportsCategoryFold.colour(for: .uncategorised), NomiColor.warningFill)
  }

  /// `ReviewQueueLogic` (S4) keeps this id out of its tiles. Changing it changes that screen.
  func testOtherOverflowIDIsStable() {
    XCTAssertEqual(ReportsCategoryFold.otherOverflowID.uuidString, "00000000-0000-0000-0000-0000000000FE")
  }

  func testPercentRoundsToWholePercent() {
    XCTAssertEqual(ReportsCategoryFold.percent(0.514), 51)
    XCTAssertEqual(ReportsCategoryFold.percent(0.996), 100)
  }
}
