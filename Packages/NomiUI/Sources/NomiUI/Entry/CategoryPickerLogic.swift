import Foundation

/// The decision behind the category picker's "New category" row, as a pure
/// function, so a test can drive it without a view.
///
/// The picker opens `CategoryEditorSheet` to create a category, so no category
/// is being edited and every name the picker holds is checked. That is the
/// same list `CategoriesScreen` passes on create. Editing leaves the edited
/// row out instead, which is why the edit path is not this function.
enum CategoryPickerLogic {
  /// The names a new category is checked against: all of them, unfiltered.
  static func createNames(from categoryNames: [String]) -> [String] {
    categoryNames
  }
}
