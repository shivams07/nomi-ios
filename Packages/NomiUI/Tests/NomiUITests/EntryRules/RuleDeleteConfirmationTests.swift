import XCTest
@testable import NomiUI

/// Y7: a swipe-delete on a user rule asks first. The copy is pinned exactly,
/// because it states what the delete keeps (categories) and what it stops
/// (matching future transactions).
final class RuleDeleteConfirmationTests: XCTestCase {
  func testTitle() {
    XCTAssertEqual(RuleDeleteConfirmation.title, "Delete this rule?")
  }

  func testMessage() {
    XCTAssertEqual(
      RuleDeleteConfirmation.message,
      "Transactions it already categorised keep their category. New transactions won’t be matched by it."
    )
  }

  func testConfirmButtonTitle() {
    XCTAssertEqual(RuleDeleteConfirmation.confirm, "Delete")
  }

  /// The back-out. The alert must always carry a visible Cancel (R9b).
  func testCancelButtonTitle() {
    XCTAssertEqual(RuleDeleteConfirmation.cancel, "Cancel")
  }
}
