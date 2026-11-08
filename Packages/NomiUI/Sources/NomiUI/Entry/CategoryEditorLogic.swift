import Foundation
import NomiCore

/// The decisions the category editor makes, as pure functions: what Save
/// enables, which refusal shows under the name, what a store error says, and
/// whether an edit has changed anything. No SwiftUI and no store, so each
/// decision is tested on its own.
///
/// The name rules are not repeated here. `CategoryEditRules` (NomiCore) is the
/// one place they live, and the store runs the same function on save. The
/// editor calls it too, so a refusal shows while the user types instead of
/// only after Save.
enum CategoryEditorLogic {
  /// The three fields the editor edits, as the user has left them.
  struct Draft: Equatable {
    var name: String
    var paletteSlot: Int
    var symbolName: String
  }

  /// Whether a delete row or a "System category" caption sits at the foot of
  /// the editor. One value drives both the view and `mayDelete`, so the row
  /// can never be offered for a category the delete guard would refuse.
  enum DeleteFooter: Equatable {
    case deleteRow
    case systemCaption
  }

  /// The first refusal the store would give this draft, or nil when it would
  /// accept it. `existingNames` must leave out the category being edited, so
  /// keeping its own name, in any case, is not a duplicate.
  static func refusal(for draft: Draft, existingNames: [String]) -> CategoryUpdateError? {
    do {
      _ = try CategoryEditRules.validate(
        name: draft.name,
        symbolName: draft.symbolName,
        paletteSlot: draft.paletteSlot,
        otherNames: existingNames
      )
      return nil
    } catch let error as CategoryUpdateError {
      return error
    } catch {
      return nil
    }
  }

  /// The line shown under the name field while the user types. Only a
  /// duplicate shows here. An empty name just leaves Save disabled, as it
  /// always has, and the other refusals appear when Save is tried.
  static func nameMessage(for draft: Draft, existingNames: [String]) -> String? {
    guard case .duplicateName(let name)? = refusal(for: draft, existingNames: existingNames) else {
      return nil
    }
    return duplicateMessage(name)
  }

  /// Whether Save is enabled. A name must be present and pass the store's
  /// rules. An existing category also has to differ from how it was loaded,
  /// so Save never writes an unchanged row. A new category needs only a valid
  /// name.
  static func canSave(_ draft: Draft, original: Draft?, existingNames: [String]) -> Bool {
    guard CategoryFormGate.isValid(name: draft.name) else { return false }
    guard refusal(for: draft, existingNames: existingNames) == nil else { return false }
    guard let original else { return true }
    return isDirty(draft, original: original)
  }

  /// Whether the draft differs from the category as it was loaded. The name is
  /// compared as the store would keep it, so adding or removing spaces alone
  /// does not count as a change.
  static func isDirty(_ draft: Draft, original: Draft) -> Bool {
    CategoryEditRules.normalizedName(draft.name) != CategoryEditRules.normalizedName(original.name)
      || draft.paletteSlot != original.paletteSlot
      || draft.symbolName != original.symbolName
  }

  /// The inline message for a failed save. A `CategoryUpdateError` gets a line
  /// that says what to fix. Anything else gets the generic line.
  static func saveMessage(for error: Error) -> String {
    guard let updateError = error as? CategoryUpdateError else {
      return "Could not save category."
    }
    switch updateError {
    case .notSupported:
      return "Could not save category."
    case .notFound:
      return "This category no longer exists."
    case .emptyName:
      return "Enter a name for the category."
    case .duplicateName(let name):
      return duplicateMessage(name)
    case .paletteSlotOutOfRange:
      return "Pick one of the seven colours."
    case .invalidSymbolName:
      return "Pick one of the icons."
    }
  }

  /// Whether the editor may send a delete for this category. `performDelete`
  /// checks it before calling the store, and `deleteFooter` reads the same
  /// rule, so a system category is never offered a delete row.
  static func mayDelete<T: SystemFlagged>(_ item: T) -> Bool {
    CategoryDeletion.isDeletable(item)
  }

  static func deleteFooter<T: SystemFlagged>(for item: T) -> DeleteFooter {
    mayDelete(item) ? .deleteRow : .systemCaption
  }

  /// The copy names the category the store would collide with. The name is
  /// the normalised one the store reports, so it reads as it would be saved.
  static func duplicateMessage(_ name: String) -> String {
    "A category named \(name) already exists."
  }
}
