import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// Anything with `isSystem` can be checked for deletability — pulled out as a
/// pure predicate so "system categories undeletable" is testable with no
/// container, rather than because none can be built; one can, under XCTest
/// (see `InMemoryModelContainer`'s measured note in NomiCore).
/// `CategoryStore.delete` already enforces this store-side; this
/// is the UI-side check that keeps the swipe action from ever being offered
/// in the first place.
protocol SystemFlagged {
  var isSystem: Bool { get }
}

extension NomiCore.Category: SystemFlagged {}

/// The category delete rules and copy, shared by the list's swipe accelerator
/// and the editor's Delete row so the two cannot drift apart.
enum CategoryDeletion {
  static func isDeletable<T: SystemFlagged>(_ item: T) -> Bool {
    !item.isSystem
  }

  /// "Delete Transport?", the delete alert's title (DeleteCategoryConfirm).
  static func alertTitle(for name: String) -> String {
    "Delete \(name)?"
  }

  /// The delete alert's message. True against `SwiftDataCategoryStore.delete`
  /// (Packages/NomiApp/Sources/NomiApp/Stores/SwiftDataCategoryStore.swift):
  /// it clears the category from every transaction that carries it (they
  /// become uncategorized), deletes every `Rule` and every `Budget` whose
  /// `categoryID` is this category, then deletes the category row. Nothing is
  /// soft-deleted, so nothing can be restored.
  static let alertMessage = "Its rules and budget will be deleted too, and its transactions become uncategorized. This can't be undone."

  /// The blocking alert's title, for a swipe on a system category or a failed
  /// delete.
  static let blockedTitle = "Can't delete category"
}

/// The Categories screen (U6; OR2). Shape from the approved `Categories` and
/// `DeleteCategoryConfirm` artboards: an H0 "Categories" title with "+" in the
/// nav bar, then one 60-high row per category (32 palette badge, name, a
/// "System" tag for seeded ones, chevron). Tapping a row opens the editor;
/// swipe-to-delete stays as the accelerator. Pushed into from Settings by U7 —
/// public so that unit can construct it without reaching into `NomiUI`'s
/// internals.
public struct CategoriesScreen: View {
  public let categoryStore: CategoryStore

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @State private var editingCategory: NomiCore.Category?
  @State private var isCreating = false
  @State private var deleteErrorMessage: String?
  @State private var pendingDeletion: NomiCore.Category?

  public init(categoryStore: CategoryStore) {
    self.categoryStore = categoryStore
  }

  public var body: some View {
    List {
      ForEach(categories) { category in
        row(for: category)
      }
      .onDelete(perform: delete)
    }
    .scrollContentBackground(.hidden)
    #if os(iOS)
    .listStyle(.insetGrouped)
    #endif
    .background(NomiColor.ground)
    .navigationTitle("Categories")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          isCreating = true
        } label: {
          NomiNavIcon(systemName: "plus")
        }
        .accessibilityLabel("New category")
      }
    }
    .sheet(isPresented: $isCreating) {
      CategoryEditorSheet(categoryStore: categoryStore, category: nil)
    }
    .sheet(item: $editingCategory) { category in
      CategoryEditorSheet(categoryStore: categoryStore, category: category)
    }
    .alert(
      CategoryDeletion.blockedTitle,
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
    .alert(
      pendingDeletion.map { CategoryDeletion.alertTitle(for: $0.name) } ?? "Delete category?",
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { if !$0 { pendingDeletion = nil } }
      ),
      actions: {
        Button("Cancel", role: .cancel) { pendingDeletion = nil }
        Button("Delete", role: .destructive) {
          if let category = pendingDeletion { confirmDelete(category) }
        }
      },
      message: {
        Text(CategoryDeletion.alertMessage)
      }
    )
  }

  /// One 60-high row. The whole row is a `Button` that opens the editor. The
  /// swipe delete is on the `ForEach` (`onDelete`) and asks first.
  private func row(for category: NomiCore.Category) -> some View {
    Button {
      editingCategory = category
    } label: {
      HStack(spacing: 12) {
        NomiCategoryBadge(symbolName: category.symbolName, paletteSlot: category.paletteSlot, size: 32)
        Text(category.name)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .lineLimit(1)
        Spacer(minLength: NomiSpacing.xs)
        if category.isSystem {
          Text("System")
            .nomiTextStyle(.footnote)
            .foregroundStyle(NomiColor.inkSecondary)
        }
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .listRowBackground(NomiColor.card)
  }

  private func delete(at offsets: IndexSet) {
    for index in offsets {
      let category = categories[index]
      guard CategoryDeletion.isDeletable(category) else {
        deleteErrorMessage = "\(category.name) is a system category and can't be deleted."
        continue
      }
      pendingDeletion = category
    }
  }

  private func confirmDelete(_ category: NomiCore.Category) {
    do {
      try categoryStore.delete(category.id)
    } catch {
      deleteErrorMessage = "Couldn't delete \(category.name)."
    }
    pendingDeletion = nil
  }
}

#Preview("Categories — default, light") {
  NavigationStack {
    CategoriesScreen(categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.light)
}

#Preview("Categories — accessibility 3, light") {
  NavigationStack {
    CategoriesScreen(categoryStore: FakeCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.light)
}

/// The delete alert is a plain view modifier, so it is previewed in isolation
/// with a `.constant(true)` presentation binding standing in for the real one.
/// Title and message come from `CategoryDeletion`, the same values the screen
/// and the editor use.
#Preview("Categories — delete confirmation, light") {
  Color.clear
    .alert(CategoryDeletion.alertTitle(for: "Transport"), isPresented: .constant(true)) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {}
    } message: {
      Text(CategoryDeletion.alertMessage)
    }
    .background(NomiColor.ground)
    .preferredColorScheme(.light)
}

private struct CategoriesScreenDeleteFailure: Error {}

/// Delete always throws, so swiping to delete a non-system category and
/// confirming the alert in the canvas exercises the `deleteErrorMessage`
/// alert — the UI-side `CategoryDeletion.isDeletable` gate only covers the
/// system-category case, not a genuine store failure like this one.
@MainActor
private final class AlwaysFailingCategoryStore: CategoryStore {
  func create(name: String, symbolName: String, paletteSlot: Int) throws -> NomiCore.Category {
    NomiCore.Category(name: name, symbolName: symbolName, paletteSlot: paletteSlot)
  }
  func rename(_ id: UUID, to name: String) throws {}
  func delete(_ id: UUID) throws { throw CategoriesScreenDeleteFailure() }
}

#Preview("Categories — delete fails, light") {
  NavigationStack {
    CategoriesScreen(categoryStore: AlwaysFailingCategoryStore())
  }
  .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
  .preferredColorScheme(.light)
}
