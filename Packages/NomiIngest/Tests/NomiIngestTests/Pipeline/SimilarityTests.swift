import Foundation
import XCTest

@testable import NomiIngest

/// The near-match threshold. Unlike the UPI parser this may drift between
/// versions without corrupting history (§2.4) — it feeds merge behaviour, not
/// `dedupeKey` — but the boundary is worth pinning so a change is a decision
/// rather than an accident.
final class SimilarityTests: XCTestCase {

  func testIdenticalStringsScoreOne() {
    XCTAssertEqual(Similarity.ratio("SWIGGY ORDER", "SWIGGY ORDER"), 1.0)
  }

  func testEmptyAgainstNonEmptyScoresZero() {
    XCTAssertEqual(Similarity.ratio("", "SWIGGY"), 0.0)
    XCTAssertEqual(Similarity.ratio("SWIGGY", ""), 0.0)
  }

  func testOneCharacterInTwentyOneClearsTheThreshold() {
    let score = Similarity.ratio("SWIGGY ORDER PAYMENT", "SWIGGY ORDER PAYMENTS")
    XCTAssertGreaterThanOrEqual(score, DedupeMatcher.nearSimilarityThreshold)
  }

  func testDifferentMerchantsFallWellBelowTheThreshold() {
    let score = Similarity.ratio("SWIGGY ORDER", "BLINKIT GROCERY")
    XCTAssertLessThan(score, DedupeMatcher.nearSimilarityThreshold)
  }

  func testTheMeasureIsSymmetric() {
    let a = Similarity.ratio("HDFC UPI SWIGGY", "HDFC UPI SWIGY")
    let b = Similarity.ratio("HDFC UPI SWIGY", "HDFC UPI SWIGGY")
    XCTAssertEqual(a, b)
  }

  func testTheCandidateWindowIsTwoDaysEitherSide() {
    let calendar = Fixture.calendar
    let range = DedupeMatcher.candidateDateRange(for: Fixture.date("2026-08-20"), calendar: calendar)

    XCTAssertTrue(range.contains(Fixture.date("2026-08-18")))
    XCTAssertTrue(range.contains(Fixture.date("2026-08-22 23:59")))
    XCTAssertFalse(range.contains(Fixture.date("2026-08-17 23:59")))
    XCTAssertFalse(range.contains(Fixture.date("2026-08-23 00:01")))
  }
}
