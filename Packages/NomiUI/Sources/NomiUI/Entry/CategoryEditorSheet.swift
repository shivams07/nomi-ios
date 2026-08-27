import NomiCore
import NomiPreview
import SwiftUI

/// Whether the entry sheet's amount is the only required field — same shape
/// of policy as `EntrySaveGate`, extracted so it is testable on its own.
enum CategoryFormGate {
  static func isValid(name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// v5: colour is picked from the fixed seven-slot palette, never a free
/// colour well (§2.6).
enum PaletteSlotOptions {
  static let all: [Int] = Array(CategoryPalette.slots.indices)
  static let symbolChoices = ["tag", "fork.knife", "bag", "car", "bolt", "house", "heart", "gamecontroller"]
  static let defaultSymbol = "tag"
}

/// Create-or-rename sheet for a category. `CategoryStore` only exposes
/// `create(name:symbolName:paletteSlot:)`, `rename(_:to:)` and `delete(_:)` —
/// there is no store method to change an EXISTING category's colour or icon,
/// so the palette/symbol pickers only render when creating. Editing an
/// existing category is rename-only until that store method exists; flagged
/// in the PR rather than silently building controls that would have nowhere
/// to persist their change.
struct CategoryEditorSheet: View {
  let categoryStore: CategoryStore
  let category: NomiCore.Category?
  var onCreated: ((UUID) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var selectedPaletteSlot: Int
  @State private var symbolName: String
  @State private var errorMessage: String?

  init(categoryStore: CategoryStore, category: NomiCore.Category?, onCreated: ((UUID) -> Void)? = nil) {
    self.categoryStore = categoryStore
    self.category = category
    self.onCreated = onCreated
    _name = State(initialValue: category?.name ?? "")
    _selectedPaletteSlot = State(initialValue: category?.paletteSlot ?? 0)
    _symbolName = State(initialValue: category?.symbolName ?? PaletteSlotOptions.defaultSymbol)
  }

  private var isCreating: Bool { category == nil }
  private var canSave: Bool { CategoryFormGate.isValid(name: name) }

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("Category name", text: $name)
        }
        if isCreating {
          Section("Colour") { paletteRow }
          Section("Icon") { symbolRow }
        }
        if let errorMessage {
          Section {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.overBudget)
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle(isCreating ? "New Category" : "Edit Category")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }
            .disabled(!canSave)
        }
      }
    }
  }

  private var paletteRow: some View {
    HStack(spacing: NomiSpacing.xs) {
      ForEach(PaletteSlotOptions.all, id: \.self) { slot in
        Circle()
          .fill(paletteSlot(slot))
          .frame(width: 28, height: 28)
          .overlay(
            Circle()
              .stroke(NomiColor.textPrimary, lineWidth: selectedPaletteSlot == slot ? 2 : 0)
          )
          .onTapGesture { selectedPaletteSlot = slot }
      }
    }
  }

  private var symbolRow: some View {
    HStack(spacing: NomiSpacing.sm) {
      ForEach(PaletteSlotOptions.symbolChoices, id: \.self) { symbol in
        Image(systemName: symbol)
          .foregroundStyle(symbolName == symbol ? NomiColor.accent : NomiColor.textSecondary)
          .onTapGesture { symbolName = symbol }
      }
    }
  }

  private func save() {
    guard canSave else { return }
    do {
      if let category {
        try categoryStore.rename(category.id, to: name)
        dismiss()
      } else {
        let created = try categoryStore.create(name: name, symbolName: symbolName, paletteSlot: selectedPaletteSlot)
        onCreated?(created.id)
        dismiss()
      }
    } catch {
      errorMessage = "Could not save category."
    }
  }
}

#Preview("Category editor — create, dark") {
  CategoryEditorSheet(categoryStore: FakeCategoryStore(), category: nil)
    .preferredColorScheme(.dark)
}

#Preview("Category editor — rename, dark") {
  CategoryEditorSheet(categoryStore: FakeCategoryStore(), category: EntryRulesPreviewSupport.makeCategories().first)
    .preferredColorScheme(.dark)
}
