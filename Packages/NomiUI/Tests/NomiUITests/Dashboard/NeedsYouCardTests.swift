import SwiftUI
import XCTest
@testable import NomiUI

/// The Review card's layout decision. The Review button shares the card's row at
/// the standard sizes and moves under the copy at accessibility sizes, so the
/// card's words wrap instead of being squeezed beside the button.
final class NeedsYouCardTests: XCTestCase {
  func testReviewButtonSharesTheRowOnlyAtStandardSizes() {
    XCTAssertFalse(NeedsYouCard.reviewButtonStacks(.xSmall))
    XCTAssertFalse(NeedsYouCard.reviewButtonStacks(.large))
    XCTAssertFalse(NeedsYouCard.reviewButtonStacks(.xxxLarge))
    XCTAssertTrue(NeedsYouCard.reviewButtonStacks(.accessibility1))
    XCTAssertTrue(NeedsYouCard.reviewButtonStacks(.accessibility3))
    XCTAssertTrue(NeedsYouCard.reviewButtonStacks(.accessibility5))
  }
}
