import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// Presented only when the entry sheet's category chip is tapped, an optional
/// step outside the save path. Reads the live category list through `@Query`
/// per the read/write asymmetry rule (Contracts §"Read/write asymmetry"); writes
/// (creating a category) still go through `CategoryStore`.
///
/// Medium detent, Cancel only, and a row tap commits (Category artboard). The
/// rows sit in one grouped card, with "New category" as the last row.
struct CategoryPickerSheet: View {
  let categoryStore: CategoryStore
  @Binding var selection: UUID?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
          VStack(spacing: 0) {
            ForEach(categories) { category in
              categoryRow(for: category)
            }
            newCategoryRow
          }
          .nomiCard(padding: EdgeInsets())
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("Category")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .sheet(isPresented: $isCreating) {
        CategoryEditorSheet(categoryStore: categoryStore, category: nil) { newID in
          selection = newID
          dismiss()
        }
      }
    }
    .nomiSheet(detents: [.medium])
  }

  /// Always followed by "New category", so every category row carries a divider.
  private func categoryRow(for category: NomiCore.Category) -> some View {
    let isSelected = selection == category.id
    return Button {
      selection = category.id
      dismiss()
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Circle()
          .fill(paletteSlot(category.paletteSlot))
          .frame(width: 10, height: 10)
          .accessibilityHidden(true)
        Text(category.name)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xs)
        if isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(NomiColor.navy)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(NomiColor.separator)
          .frame(height: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }

  private var newCategoryRow: some View {
    Button {
      isCreating = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        Image(systemName: "plus")
          .accessibilityHidden(true)
        Text("New category")
          .nomiTextStyle(.body)
        Spacer(minLength: 0)
      }
      .foregroundStyle(NomiColor.navy)
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview("Category picker · light") {
  CategoryPickerSheet(categoryStore: FakeCategoryStore(), selection: .constant(nil))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
    .preferredColorScheme(.light)
}
