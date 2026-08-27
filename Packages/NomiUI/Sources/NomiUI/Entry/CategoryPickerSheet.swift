import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// Presented only when the entry sheet's category chip is tapped — an EXTRA,
/// optional step outside the two-tap save path. Reads the live category list
/// through `@Query` per the read/write asymmetry rule (Contracts §"Read/write
/// asymmetry"); writes (creating a category) still go through `CategoryStore`.
struct CategoryPickerSheet: View {
  let categoryStore: CategoryStore
  @Binding var selection: UUID?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Environment(\.dismiss) private var dismiss
  @State private var isCreating = false

  var body: some View {
    NavigationStack {
      List {
        ForEach(categories) { category in
          Button {
            selection = category.id
            dismiss()
          } label: {
            HStack(spacing: NomiSpacing.xs) {
              Circle()
                .fill(paletteSlot(category.paletteSlot))
                .frame(width: 10, height: 10)
              Text(category.name)
                .nomiTextStyle(.body)
                .foregroundStyle(NomiColor.textPrimary)
              Spacer()
              if selection == category.id {
                Image(systemName: "checkmark")
                  .foregroundStyle(NomiColor.accent)
              }
            }
          }
          .listRowBackground(NomiColor.surfaceRaised)
        }
        Button {
          isCreating = true
        } label: {
          Label("New Category", systemImage: "plus")
            .foregroundStyle(NomiColor.accent)
        }
        .listRowBackground(NomiColor.surfaceRaised)
      }
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
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
  }
}

#Preview("Category picker, dark") {
  CategoryPickerSheet(categoryStore: FakeCategoryStore(), selection: .constant(nil))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
    .preferredColorScheme(.dark)
}
