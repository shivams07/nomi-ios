import Foundation

/// The decision behind the category picker's "New category" row, as a pure
/// function, so a test can drive it without a view.
///
/// The picker opens `CategoryEditorSheet` to create a category, so no category
/// is being edited and every name the picker holds is checked. That is the
/// same list `CategoriesScreen` passes on create. Editing leaves the edited
/// row out instead, which is why the edit path is not this function.
enum CategoryPickerLogic {
  /// One row of the picker. `unset` is the "None" row, offered only when the
  /// picker allows no category, and it clears the selection.
  enum Row: Hashable {
    case unset
    case category(UUID)
  }

  /// The rows in display order. "None" leads when `allowsNone`, then every
  /// category in the order the store lists them. Without `allowsNone` the rows
  /// are the categories alone.
  static func rows(categoryIDs: [UUID], allowsNone: Bool) -> [Row] {
    let categories = categoryIDs.map(Row.category)
    return allowsNone ? [.unset] + categories : categories
  }

  /// The names a new category is checked against: all of them, unfiltered.
  static func createNames(from categoryNames: [String]) -> [String] {
    categoryNames
  }
}
