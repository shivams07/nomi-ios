import Foundation
import NomiCore

public enum CategoryStoreError: Error {
  case systemCategory
}

@MainActor
public final class FakeCategoryStore: CategoryStore {
  public var categories: [Category]

  public init(categories: [Category] = PreviewData.categories) {
    self.categories = categories
  }

  public func create(name: String, symbolName: String, paletteSlot: Int) throws -> Category {
    let category = Category(name: name, symbolName: symbolName, paletteSlot: paletteSlot, sortIndex: categories.count)
    categories.append(category)
    return category
  }

  public func rename(_ id: UUID, to name: String) throws {
    guard let category = categories.first(where: { $0.id == id }) else { return }
    category.name = name
  }

  public func delete(_ id: UUID) throws {
    guard let category = categories.first(where: { $0.id == id }) else { return }
    if category.isSystem { throw CategoryStoreError.systemCategory }
    categories.removeAll { $0.id == id }
  }
}
