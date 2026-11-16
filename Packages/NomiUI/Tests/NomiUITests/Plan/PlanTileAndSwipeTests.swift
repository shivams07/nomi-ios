import CoreGraphics
import XCTest

@testable import NomiUI

/// Budget tile names never split inside a word (PR #221, Lim), and a recurring row
/// removed by a full swipe (Corrections 13: no Undo).
final class PlanTileAndSwipeTests: XCTestCase {
  func testTwoWordNameMayWrapToTwoLines() {
    XCTAssertEqual(PlanLogic.tileNameLineLimit("Food & Dining"), 2)
    XCTAssertEqual(PlanLogic.tileNameLineLimit("Entertainment subscriptions"), 2)
  }

  /// A single long word is one line. It scales down or truncates, so it never breaks
  /// between letters.
  func testSingleWordNameStaysOnOneLine() {
    XCTAssertEqual(PlanLogic.tileNameLineLimit("Shopping"), 1)
    XCTAssertEqual(PlanLogic.tileNameLineLimit("Entertainmentsubscriptions"), 1)
  }

  func testBlankNameStaysOnOneLine() {
    XCTAssertEqual(PlanLogic.tileNameLineLimit(""), 1)
  }

  func testShortLeftwardDragRests() {
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: -20, isRevealed: false), .rest)
  }

  func testMediumLeftwardDragReveals() {
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: -90, isRevealed: false), .reveal)
  }

  /// A full swipe removes the row, with no second tap.
  func testFullLeftwardSwipeDismisses() {
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: -240, isRevealed: false), .dismiss)
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: -220, isRevealed: false), .dismiss)
  }

  func testRevealedRowStaysOpenOnAFurtherLeftwardDrag() {
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: -10, isRevealed: true), .reveal)
  }

  func testRightwardDragFromRestRests() {
    XCTAssertEqual(PlanLogic.recurringSwipeOutcome(translationWidth: 40, isRevealed: false), .rest)
  }
}
