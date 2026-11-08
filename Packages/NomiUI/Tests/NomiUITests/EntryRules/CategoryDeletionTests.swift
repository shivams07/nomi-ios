import XCTest
@testable import NomiUI

/// Exercises `CategoryDeletion.isDeletable` against a plain stub, never a
/// real `Category`. Not because one cannot be built: a container constructs
/// fine under XCTest and only swift-testing traps (see
/// `InMemoryModelContainer`'s measured note in NomiCore). `SystemFlagged` is
/// the entire input the rule reads, so a stub exercises it with nothing else
/// in the way.
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

  /// The alert names the category it will delete, with the question mark the
  /// artboard uses ("Delete Transport?").
  func testAlertTitleNamesTheCategory() {
    XCTAssertEqual(CategoryDeletion.alertTitle(for: "Transport"), "Delete Transport?")
  }

  /// Copy pinned to what `SwiftDataCategoryStore.delete` does: rules and the
  /// budget go with the category, its transactions become uncategorized, and
  /// nothing is soft-deleted, so "can't be undone" stays true.
  func testAlertMessageMatchesStoreDeleteBehaviour() {
    XCTAssertEqual(
      CategoryDeletion.alertMessage,
      "Its rules and budget will be deleted too, and its transactions become uncategorized. This can't be undone."
    )
  }
}
