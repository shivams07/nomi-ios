import NomiCore
import SwiftData

/// Preview-only `ModelContainer` scaffolding for the screens in `Entry/**`
/// and `Rules/**` that read through `@Query`. Each call builds a FRESH,
/// in-memory container rather than reusing `InMemoryModelContainer.shared` —
/// that singleton is shared process-wide, and repeatedly inserting the same
/// seed objects into it across many `#Preview` blocks would accumulate rows
/// across canvas runs. Not exercised by `swift test`: SwiftData's headless
/// bundle-name lookup fails before any of this runs (see
/// `InMemoryModelContainer`'s note in NomiCore) — these helpers exist purely
/// for Xcode canvas / on-device preview use, which this team cannot run
/// locally either, so their real verification is Shivam's.
enum EntryRulesPreviewSupport {
  static func makeCategories() -> [NomiCore.Category] {
    [
      NomiCore.Category(name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0),
      NomiCore.Category(name: "Shopping", symbolName: "bag", paletteSlot: 1, isSystem: true, sortIndex: 1),
      NomiCore.Category(name: "Transport", symbolName: "car", paletteSlot: 2, isSystem: false, sortIndex: 2),
      NomiCore.Category(name: "Bills & Utilities", symbolName: "bolt", paletteSlot: 3, isSystem: true, sortIndex: 3),
    ]
  }

  /// `ModelContainer.mainContext` is `@MainActor`-isolated; these two builders
  /// are only ever called from `#Preview` closures, which already run on the
  /// main actor, so this annotation just tells the (targeted) concurrency
  /// checker what's already true rather than changing behaviour.
  @MainActor
  static func makeCategoryContainer(seed: [NomiCore.Category]? = nil) -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Category.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    for category in seed ?? makeCategories() {
      container.mainContext.insert(category)
    }
    return container
  }

  @MainActor
  static func makeRulesContainer() -> ModelContainer {
    let container = try! ModelContainer(
      for: Schema([NomiCore.Category.self, NomiCore.Rule.self]),
      configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    let categories = makeCategories()
    for category in categories {
      container.mainContext.insert(category)
    }
    container.mainContext.insert(NomiCore.Rule(pattern: "*SWIGGY*", categoryID: categories[0].id, priority: 0))
    container.mainContext.insert(NomiCore.Rule(pattern: "*AMAZON*", categoryID: categories[1].id, priority: 1))
    return container
  }
}
