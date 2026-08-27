import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// Anything with `isSystem` can be checked for deletability — pulled out as a
/// pure predicate so "system categories undeletable" is testable without
/// constructing an `@Model` instance (this package's `swift test` runner
/// cannot do that headlessly; see `InMemoryModelContainer`'s note in
/// NomiCore). `CategoryStore.delete` already enforces this store-side; this
/// is the UI-side check that keeps the swipe action from ever being offered
/// in the first place.
protocol SystemFlagged {
  var isSystem: Bool { get }
}

extension NomiCore.Category: SystemFlagged {}

enum CategoryDeletion {
  static func isDeletable<T: SystemFlagged>(_ item: T) -> Bool {
    !item.isSystem
  }
}

/// The Categories screen (U6). Pushed into from Settings by U7 — public so
/// that unit can construct it without reaching into `NomiUI`'s internals.
public struct CategoriesScreen: View {
  public let categoryStore: CategoryStore

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingCategory: NomiCore.Category?
  @State private var isCreating = false
  @State private var deleteErrorMessage: String?

  public init(categoryStore: CategoryStore) {
    self.categoryStore = categoryStore
  }

  public var body: some View {
    List {
      ForEach(categories) { category in
        row(for: category)
          .contentShape(Rectangle())
          .onTapGesture { editingCategory = category }
      }
      .onDelete(perform: delete)
    }
    .scrollContentBackground(.hidden)
    .background(NomiColor.surfaceCanvas)
    .navigationTitle("Categories")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreating = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(isPresented: $isCreating) {
      CategoryEditorSheet(categoryStore: categoryStore, category: nil)
    }
    .sheet(item: $editingCategory) { category in
      CategoryEditorSheet(categoryStore: categoryStore, category: category)
    }
    .alert(
      "Can't delete category",
      isPresented: Binding(
        get: { deleteErrorMessage != nil },
        set: { if !$0 { deleteErrorMessage = nil } }
      ),
      actions: {
        Button("OK") { deleteErrorMessage = nil }
      },
      message: {
        Text(deleteErrorMessage ?? "")
      }
    )
  }

  private func row(for category: NomiCore.Category) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Circle()
        .fill(paletteSlot(category.paletteSlot))
        .frame(width: 10, height: 10)
      Image(systemName: category.symbolName)
        .foregroundStyle(NomiColor.textSecondary)
      Text(category.name)
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
      Spacer()
      if category.isSystem {
        Text("System")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      let category = categories[index]
      guard CategoryDeletion.isDeletable(category) else {
        deleteErrorMessage = "\(category.name) is a system category and can't be deleted."
        continue
      }
      try? categoryStore.delete(category.id)
    }
  }
}

#Preview("Categories — default, dark") {
  NavigationStack {
    CategoriesScreen(categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.dark)
}

#Preview("Categories — accessibility 3, dark") {
  NavigationStack {
    CategoriesScreen(categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
