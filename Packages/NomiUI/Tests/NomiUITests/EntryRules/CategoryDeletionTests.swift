import XCTest
@testable import NomiUI

/// Exercises `CategoryRowRules.canDelete` against a plain stub, never a
/// real `Category`. Not because one cannot be built: a container constructs
/// fine under XCTest and only swift-testing traps (see
/// `InMemoryModelContainer`'s measured note in NomiCore). `SystemFlagged` is
/// the entire input the rule reads, so a stub exercises it with nothing else
/// in the way.
private struct StubCategory: SystemFlagged {
  let isSystem: Bool
}

final class CategoryDeletionTests: XCTestCase {
  /// The swipe on a system row is disabled by this rule, so it shows nothing.
  func testSystemCategoryIsNotDeletable() {
    XCTAssertFalse(CategoryRowRules.canDelete(StubCategory(isSystem: true)))
  }

  func testCustomCategoryIsDeletable() {
    XCTAssertTrue(CategoryRowRules.canDelete(StubCategory(isSystem: false)))
  }

  /// The swipe filter. A system row never survives it, so the delete path never
  /// asks the store to delete one, even when the list hands over its offset.
  func testDeletableOffsetsDropsSystemRows() {
    let items = [StubCategory(isSystem: false), StubCategory(isSystem: true), StubCategory(isSystem: false)]
    XCTAssertEqual(CategoryRowRules.deletableOffsets(IndexSet([0, 1, 2]), in: items), IndexSet([0, 2]))
  }

  func testDeletableOffsetsOfOnlySystemRowsIsEmpty() {
    let items = [StubCategory(isSystem: true), StubCategory(isSystem: true)]
    XCTAssertEqual(CategoryRowRules.deletableOffsets(IndexSet([0, 1]), in: items), IndexSet())
  }

  /// An offset that names no row is dropped rather than indexing past the list.
  func testDeletableOffsetsIgnoresIndexesOutsideTheList() {
    let items = [StubCategory(isSystem: false)]
    XCTAssertEqual(CategoryRowRules.deletableOffsets(IndexSet([0, 5]), in: items), IndexSet([0]))
  }

  /// `.deleteDisabled` cannot be driven from a unit test, so this pins its
  /// presence in the source. Removing the modifier from the system rows fails it.
  func testSystemRowsCarryDeleteDisabledInTheList() throws {
    let source = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // EntryRules
      .deletingLastPathComponent() // NomiUITests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // NomiUI (package root)
      .appendingPathComponent("Sources/NomiUI/Entry/CategoriesScreen.swift")
    let text = try String(contentsOf: source, encoding: .utf8)
    XCTAssertTrue(text.contains(".deleteDisabled(category.isSystem)"))
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
