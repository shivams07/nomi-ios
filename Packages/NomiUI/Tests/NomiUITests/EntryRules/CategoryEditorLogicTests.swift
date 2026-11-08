import Foundation
import NomiCore
import Testing
@testable import NomiUI

/// Tests for `CategoryEditorLogic`, the pure decisions behind the category
/// editor. The store is never touched: the store's own rules are the ones
/// `CategoryEditRules` already tests, and these tests check what the editor
/// does with them.
///
/// The delete guard is tested on a plain stub. `SystemFlagged` is the entire
/// input the rule reads, so no container is needed.
private struct StubCategory: SystemFlagged {
  let isSystem: Bool
}

private struct UnknownFailure: Error {}

private let transport = CategoryEditorLogic.Draft(name: "Transport", paletteSlot: 2, symbolName: "car")

/// Every other category the store holds when `Transport` is the one edited.
private let otherNames = ["Food & Dining", "Shopping", "Bills & Utilities"]

@Suite struct CategoryEditorLogicSaveGateTests {

  @Test func newCategoryWithANameCanSave() {
    let draft = CategoryEditorLogic.Draft(name: "Gifts", paletteSlot: 0, symbolName: "tag")
    #expect(CategoryEditorLogic.canSave(draft, original: nil, existingNames: otherNames))
  }

  @Test func emptyNameCannotSave() {
    let draft = CategoryEditorLogic.Draft(name: "", paletteSlot: 0, symbolName: "tag")
    #expect(!CategoryEditorLogic.canSave(draft, original: nil, existingNames: otherNames))
  }

  @Test func whitespaceOnlyNameCannotSave() {
    let draft = CategoryEditorLogic.Draft(name: " \n\t ", paletteSlot: 0, symbolName: "tag")
    #expect(!CategoryEditorLogic.canSave(draft, original: nil, existingNames: otherNames))
  }

  /// The store refuses a duplicate regardless of case, so Save must too.
  @Test func duplicateNameCannotSaveWhetherOrNotItIsNew() {
    let draft = CategoryEditorLogic.Draft(name: "shopping", paletteSlot: 0, symbolName: "tag")
    #expect(!CategoryEditorLogic.canSave(draft, original: nil, existingNames: otherNames))
    #expect(!CategoryEditorLogic.canSave(draft, original: transport, existingNames: otherNames))
  }

  @Test func paletteSlotOutsideTheSevenCannotSave() {
    let high = CategoryEditorLogic.Draft(name: "Gifts", paletteSlot: 7, symbolName: "tag")
    let low = CategoryEditorLogic.Draft(name: "Gifts", paletteSlot: -1, symbolName: "tag")
    #expect(!CategoryEditorLogic.canSave(high, original: nil, existingNames: otherNames))
    #expect(!CategoryEditorLogic.canSave(low, original: nil, existingNames: otherNames))
  }

  @Test func symbolThatIsNotASymbolShapeCannotSave() {
    let spaced = CategoryEditorLogic.Draft(name: "Gifts", paletteSlot: 0, symbolName: "fork knife")
    #expect(!CategoryEditorLogic.canSave(spaced, original: nil, existingNames: otherNames))
  }

  /// Save is off for an edit that changed nothing. Saving it would write an
  /// identical row.
  @Test func unchangedExistingCategoryCannotSave() {
    #expect(!CategoryEditorLogic.canSave(transport, original: transport, existingNames: otherNames))
  }

  @Test func renameMakesAnExistingCategorySavable() {
    var draft = transport
    draft.name = "Travel"
    #expect(CategoryEditorLogic.canSave(draft, original: transport, existingNames: otherNames))
  }

  @Test func colourChangeMakesAnExistingCategorySavable() {
    var draft = transport
    draft.paletteSlot = 5
    #expect(CategoryEditorLogic.canSave(draft, original: transport, existingNames: otherNames))
  }

  @Test func iconChangeMakesAnExistingCategorySavable() {
    var draft = transport
    draft.symbolName = "bolt"
    #expect(CategoryEditorLogic.canSave(draft, original: transport, existingNames: otherNames))
  }

  /// The edited category's own name is left out of `existingNames`, so
  /// re-casing it is a valid rename rather than a duplicate of itself.
  @Test func reCasingOwnNameIsASavableRename() {
    var draft = transport
    draft.name = "transport"
    #expect(CategoryEditorLogic.canSave(draft, original: transport, existingNames: otherNames))
  }

  /// A system category is editable like any other. Its own name is left out of
  /// `existingNames`, as the screen does for every edit.
  @Test func editsToASystemCategoryAreSavable() {
    let original = CategoryEditorLogic.Draft(name: "Food & Dining", paletteSlot: 0, symbolName: "fork.knife")
    var draft = original
    draft.paletteSlot = 3
    let namesWithoutSelf = ["Transport", "Shopping", "Bills & Utilities"]
    #expect(CategoryEditorLogic.canSave(draft, original: original, existingNames: namesWithoutSelf))
  }
}

@Suite struct CategoryEditorLogicDirtyTests {

  /// Adding or removing spaces does not change what the store would keep, so
  /// it is not a change.
  @Test func trailingSpacesAloneAreNotDirty() {
    var draft = transport
    draft.name = "Transport   "
    #expect(!CategoryEditorLogic.isDirty(draft, original: transport))
  }

  @Test func internalWhitespaceAloneIsNotDirty() {
    let original = CategoryEditorLogic.Draft(name: "Bills & Utilities", paletteSlot: 4, symbolName: "bolt")
    var draft = original
    draft.name = "Bills  &   Utilities"
    #expect(!CategoryEditorLogic.isDirty(draft, original: original))
  }

  @Test func eachFieldOnItsOwnIsDirty() {
    var name = transport
    name.name = "Travel"
    var slot = transport
    slot.paletteSlot = 0
    var symbol = transport
    symbol.symbolName = "bag"

    #expect(CategoryEditorLogic.isDirty(name, original: transport))
    #expect(CategoryEditorLogic.isDirty(slot, original: transport))
    #expect(CategoryEditorLogic.isDirty(symbol, original: transport))
  }

  @Test func identicalDraftIsNotDirty() {
    #expect(!CategoryEditorLogic.isDirty(transport, original: transport))
  }
}

@Suite struct CategoryEditorLogicNameMessageTests {

  @Test func duplicateNameShowsTheDuplicateLine() {
    var draft = transport
    draft.name = "Food & Dining"
    #expect(
      CategoryEditorLogic.nameMessage(for: draft, existingNames: otherNames)
        == "A category named Food & Dining already exists."
    )
  }

  /// The line names the category as the store would keep it: spaces collapsed,
  /// case as typed.
  @Test func duplicateLineUsesTheNormalisedName() {
    var draft = transport
    draft.name = "  food   &  dining "
    #expect(
      CategoryEditorLogic.nameMessage(for: draft, existingNames: otherNames)
        == "A category named food & dining already exists."
    )
  }

  @Test func emptyNameShowsNoLiveLine() {
    var draft = transport
    draft.name = "   "
    #expect(CategoryEditorLogic.nameMessage(for: draft, existingNames: otherNames) == nil)
  }

  @Test func uniqueNameShowsNoLiveLine() {
    var draft = transport
    draft.name = "Travel"
    #expect(CategoryEditorLogic.nameMessage(for: draft, existingNames: otherNames) == nil)
  }

  /// The edited category is not in `existingNames`, so its own name shows no
  /// line.
  @Test func keepingItsOwnNameShowsNoLiveLine() {
    #expect(CategoryEditorLogic.nameMessage(for: transport, existingNames: otherNames) == nil)
  }
}

@Suite struct CategoryEditorLogicSaveMessageTests {

  @Test func notFoundSaysTheCategoryIsGone() {
    let message = CategoryEditorLogic.saveMessage(for: CategoryUpdateError.notFound(UUID()))
    #expect(message == "This category no longer exists.")
  }

  @Test func emptyNameAsksForAName() {
    #expect(CategoryEditorLogic.saveMessage(for: CategoryUpdateError.emptyName) == "Enter a name for the category.")
  }

  @Test func duplicateSaveMessageMatchesTheLiveLine() {
    let fromStore = CategoryEditorLogic.saveMessage(for: CategoryUpdateError.duplicateName("Shopping"))
    var draft = transport
    draft.name = "Shopping"
    #expect(fromStore == CategoryEditorLogic.nameMessage(for: draft, existingNames: otherNames))
    #expect(fromStore == "A category named Shopping already exists.")
  }

  @Test func outOfRangeColourAsksForOneOfSeven() {
    #expect(
      CategoryEditorLogic.saveMessage(for: CategoryUpdateError.paletteSlotOutOfRange(9))
        == "Pick one of the seven colours."
    )
  }

  @Test func invalidIconAsksForOneOfTheIcons() {
    #expect(
      CategoryEditorLogic.saveMessage(for: CategoryUpdateError.invalidSymbolName("a b"))
        == "Pick one of the icons."
    )
  }

  @Test func notSupportedGetsTheGenericLine() {
    #expect(CategoryEditorLogic.saveMessage(for: CategoryUpdateError.notSupported) == "Could not save category.")
  }

  /// A failure that is not a `CategoryUpdateError` (a SwiftData save, for one)
  /// gets the generic line rather than a wrong specific one.
  @Test func unknownErrorGetsTheGenericLine() {
    #expect(CategoryEditorLogic.saveMessage(for: UnknownFailure()) == "Could not save category.")
  }
}

@Suite struct CategoryEditorLogicDeleteGuardTests {

  /// The guard `performDelete` runs before it calls the store. A system
  /// category must never reach `delete`.
  @Test func systemCategoryMayNotBeDeleted() {
    #expect(!CategoryEditorLogic.mayDelete(StubCategory(isSystem: true)))
  }

  @Test func customCategoryMayBeDeleted() {
    #expect(CategoryEditorLogic.mayDelete(StubCategory(isSystem: false)))
  }

  @Test func systemCategoryGetsTheCaptionNotTheRow() {
    #expect(CategoryEditorLogic.deleteFooter(for: StubCategory(isSystem: true)) == .systemCaption)
  }

  @Test func customCategoryGetsTheDeleteRow() {
    #expect(CategoryEditorLogic.deleteFooter(for: StubCategory(isSystem: false)) == .deleteRow)
  }

  /// A delete row is offered exactly when the guard lets delete through, so the
  /// two can never disagree.
  @Test func deleteRowAppearsExactlyWhenDeleteIsAllowed() {
    for isSystem in [true, false] {
      let item = StubCategory(isSystem: isSystem)
      #expect((CategoryEditorLogic.deleteFooter(for: item) == .deleteRow) == CategoryEditorLogic.mayDelete(item))
    }
  }
}
