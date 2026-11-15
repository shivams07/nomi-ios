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
///
/// `allowsNone` (S13) puts a "None" row first, which clears the selection. It is
/// off by default, so every picker that does not opt in is unchanged. The row
/// order comes from `CategoryPickerLogic.rows`.
struct CategoryPickerSheet: View {
  let categoryStore: CategoryStore
  @Binding var selection: UUID?
  var allowsNone: Bool = false

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false

  /// The leading slot every row shares, so the "None" badge and the category
  /// dots start their names on one column.
  private static let leadingSlot: CGFloat = 28

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: NomiSpacing.cardGap) {
          VStack(spacing: 0) {
            ForEach(
              CategoryPickerLogic.rows(categoryIDs: categories.map(\.id), allowsNone: allowsNone),
              id: \.self
            ) { row in
              rowView(for: row)
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
        CategoryEditorSheet(
          categoryStore: categoryStore,
          category: nil,
          existingNames: CategoryPickerLogic.createNames(from: categories.map(\.name))
        ) { newID in
          selection = newID
          dismiss()
        }
      }
    }
    .nomiSheet(detents: [.medium])
  }

  @ViewBuilder
  private func rowView(for row: CategoryPickerLogic.Row) -> some View {
    switch row {
    case .unset:
      noneRow
    case .category(let id):
      if let category = categories.first(where: { $0.id == id }) {
        categoryRow(for: category)
      }
    }
  }

  /// "None" clears the selection and dismisses. It is the selected row while no
  /// category is chosen. Its badge is the warning "questionmark" that an
  /// uncategorised row already uses.
  private var noneRow: some View {
    let isSelected = selection == nil
    return Button {
      selection = nil
      dismiss()
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        NomiCategoryBadge(
          symbolName: NomiCategoryBadge.uncategorisedSymbolName,
          paletteSlot: nil,
          size: Self.leadingSlot
        )
        .accessibilityHidden(true)
        Text("None", bundle: .module)
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
          .frame(width: Self.leadingSlot, height: Self.leadingSlot)
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

#Preview("Category picker · None first · light") {
  CategoryPickerSheet(categoryStore: FakeCategoryStore(), selection: .constant(nil), allowsNone: true)
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
    .preferredColorScheme(.light)
}
