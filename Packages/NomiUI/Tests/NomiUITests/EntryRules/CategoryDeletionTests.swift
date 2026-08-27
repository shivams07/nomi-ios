import XCTest
@testable import NomiUI

/// Exercises `CategoryDeletion.isDeletable` against a plain stub, never a
/// real `Category` — this package's CI runner cannot construct `@Model`
/// instances headlessly (see `InMemoryModelContainer`'s note in NomiCore).
private struct StubCategory: SystemFlagged {
  let isSystem: Bool
}

final class CategoryDeletionTests: XCTestCase {
  func testSystemCategoryIsNotDeletable() {
    XCTAssertFalse(CategoryDeletion.isDeletable(StubCategory(isSystem: true)))
  }

  func testCustomCategoryIsDeletable() {
    XCTAssertTrue(CategoryDeletion.isDeletable(StubCategory(isSystem: false)))
  }
}
