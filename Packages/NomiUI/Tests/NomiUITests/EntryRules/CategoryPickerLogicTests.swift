import Foundation
import NomiCore
import Testing
@testable import NomiUI

/// Tests for the "New category" path from the Add transaction sheet's category
/// picker. The picker passes every category name to `CategoryEditorSheet`, the
/// same list `CategoriesScreen` passes on create, so the same refusal applies.
/// The view itself is not rendered here; these tests cover the names it hands
/// over and the refusal `CategoryEditorLogic` gives for them.
private let pickerNames = ["Food & Dining", "Shopping", "Bills & Utilities", "Transport"]

private func newDraft(_ name: String) -> CategoryEditorLogic.Draft {
  CategoryEditorLogic.Draft(name: name, paletteSlot: 0, symbolName: "tag")
}

@Suite struct CategoryPickerLogicTests {

  /// Create checks every name. A system category is not left out of the list.
  @Test func createNamesKeepsEveryName() {
    #expect(CategoryPickerLogic.createNames(from: pickerNames) == pickerNames)
  }

  @Test func createRefusesACaseInsensitiveDuplicate() {
    let names = CategoryPickerLogic.createNames(from: pickerNames)
    let draft = newDraft("SHOPPING")
    #expect(!CategoryEditorLogic.canSave(draft, original: nil, existingNames: names))
    #expect(
      CategoryEditorLogic.nameMessage(for: draft, existingNames: names)
        == "A category named SHOPPING already exists."
    )
  }

  @Test func createRefusesADuplicateWithSurroundingWhitespace() {
    let names = CategoryPickerLogic.createNames(from: pickerNames)
    let draft = newDraft("  shopping  ")
    #expect(!CategoryEditorLogic.canSave(draft, original: nil, existingNames: names))
    #expect(
      CategoryEditorLogic.nameMessage(for: draft, existingNames: names)
        == "A category named shopping already exists."
    )
  }

  @Test func createTrimsTheNameItStores() {
    let names = CategoryPickerLogic.createNames(from: pickerNames)
    let draft = newDraft("  Travel  ")
    #expect(CategoryEditorLogic.canSave(draft, original: nil, existingNames: names))
    #expect(CategoryEditRules.normalizedName(draft.name) == "Travel")
  }

  @Test func createAllowsANewUniqueName() {
    let names = CategoryPickerLogic.createNames(from: pickerNames)
    let draft = newDraft("Travel")
    #expect(CategoryEditorLogic.canSave(draft, original: nil, existingNames: names))
    #expect(CategoryEditorLogic.nameMessage(for: draft, existingNames: names) == nil)
  }

  @Test func createKeepsSaveDisabledForAnEmptyName() {
    let names = CategoryPickerLogic.createNames(from: pickerNames)
    #expect(!CategoryEditorLogic.canSave(newDraft("   "), original: nil, existingNames: names))
  }
}

/// The picker's rows. A picker opened with `allowsNone` (S3a's rule picker) starts
/// with the "None" row, which clears the selection. Every other picker is the
/// category list alone, as it was before S13.
@Suite struct CategoryPickerRowsTests {

  @Test func rowsWithNoneStartWithTheUnsetRow() {
    let ids = [UUID(), UUID()]
    let rows = CategoryPickerLogic.rows(categoryIDs: ids, allowsNone: true)
    #expect(rows == [.unset, .category(ids[0]), .category(ids[1])])
  }

  @Test func rowsWithNoneAndNoCategoriesStillOfferNone() {
    #expect(CategoryPickerLogic.rows(categoryIDs: [], allowsNone: true) == [.unset])
  }

  @Test func rowsWithoutNoneAreTheCategoriesUnchanged() {
    let ids = [UUID(), UUID()]
    #expect(CategoryPickerLogic.rows(categoryIDs: ids, allowsNone: false) == ids.map(CategoryPickerLogic.Row.category))
  }

  @Test func noneIsOnlyEverTheFirstRow() {
    let ids = [UUID(), UUID(), UUID()]
    let rows = CategoryPickerLogic.rows(categoryIDs: ids, allowsNone: true)
    #expect(rows.filter { $0 == .unset }.count == 1)
    #expect(rows.first == .unset)
  }
}
