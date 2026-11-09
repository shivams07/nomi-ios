import Foundation
import NomiCore

public enum CategoryStoreError: Error {
  case systemCategory
}

@MainActor
public final class FakeCategoryStore: CategoryStore {
  public var categories: [NomiCore.Category]

  public init(categories: [NomiCore.Category] = PreviewData.categories) {
    self.categories = categories
  }

  /// The same rules as `SwiftDataCategoryStore.create`, so a preview refuses
  /// what the app refuses and stores the same normalised name. Nothing is
  /// appended on refusal.
  public func create(name: String, symbolName: String, paletteSlot: Int) throws -> NomiCore.Category {
    let stored = try CategoryEditRules.validate(
      name: name,
      symbolName: symbolName,
      paletteSlot: paletteSlot,
      otherNames: categories.map(\.name)
    )
    let category = NomiCore.Category(name: stored, symbolName: symbolName, paletteSlot: paletteSlot, sortIndex: categories.count)
    categories.append(category)
    return category
  }

  public func rename(_ id: UUID, to name: String) throws {
    guard let category = categories.first(where: { $0.id == id }) else { return }
    category.name = name
  }

  /// The same rules as `SwiftDataCategoryStore.update`, so a preview refuses
  /// what the app refuses.
  public func update(_ id: UUID, name: String, symbolName: String, paletteSlot: Int) throws {
    guard let category = categories.first(where: { $0.id == id }) else {
      throw CategoryUpdateError.notFound(id)
    }
    let stored = try CategoryEditRules.validate(
      name: name,
      symbolName: symbolName,
      paletteSlot: paletteSlot,
      otherNames: categories.filter { $0.id != id }.map(\.name)
    )
    category.name = stored
    category.symbolName = symbolName
    category.paletteSlot = paletteSlot
  }

  public func delete(_ id: UUID) throws {
    guard let category = categories.first(where: { $0.id == id }) else { return }
    if category.isSystem { throw CategoryStoreError.systemCategory }
    categories.removeAll { $0.id == id }
  }
}
