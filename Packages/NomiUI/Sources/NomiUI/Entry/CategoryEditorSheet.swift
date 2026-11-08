import NomiCore
import NomiPreview
import SwiftUI

/// Whether the category's name is the only required field — same shape of
/// policy as `EntrySaveGate`, extracted so it is testable on its own.
enum CategoryFormGate {
  static func isValid(name: String) -> Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

/// v5: colour is picked from the fixed seven-slot palette, never a free
/// colour well (§2.6).
enum PaletteSlotOptions {
  static let all: [Int] = Array(CategoryPalette.slots.indices)
  /// VoiceOver names for the swatches, in `CategoryPalette.slots` order.
  static let slotNames = ["Orange", "Aqua", "Yellow", "Magenta", "Green", "Violet", "Red"]
  static let symbolChoices = ["tag", "fork.knife", "bag", "car", "bolt", "house", "heart", "gamecontroller"]
  /// VoiceOver names for the icon grid, keyed by SF Symbol name.
  static let symbolNames: [String: String] = [
    "tag": "Tag",
    "fork.knife": "Food",
    "bag": "Bag",
    "car": "Car",
    "bolt": "Bolt",
    "house": "House",
    "heart": "Heart",
    "gamecontroller": "Game controller",
  ]
  static let defaultSymbol = "tag"

  static func colourName(forSlot slot: Int) -> String {
    slotNames.indices.contains(slot) ? slotNames[slot] : "Other"
  }

  static func iconName(forSymbol symbol: String) -> String {
    symbolNames[symbol] ?? symbol
  }
}

/// Create-or-edit sheet for a category (OR2; approved `CategoryEditor`
/// artboard). A large sheet with Cancel left and Save right, both text, as the
/// other form sheets do. Name sits in a card; a new category also picks its
/// colour from the seven slots and its icon from the grid.
///
/// `CategoryStore` has no method that changes an existing category's colour or
/// icon (it has `create`, `rename` and `delete` only), so for an existing
/// category the Colour and Icon sections are not shown. The artboard draws them
/// on an existing category. That is a deviation, listed in the PR: showing the
/// controls would mean controls whose change is silently dropped.
///
/// A non-system category ends with a "Delete category" row that asks first.
/// A system category shows a "System category" caption in that place.
struct CategoryEditorSheet: View {
  let categoryStore: CategoryStore
  let category: NomiCore.Category?
  var onCreated: ((UUID) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var selectedPaletteSlot: Int
  @State private var symbolName: String
  @State private var errorMessage: String?
  @State private var isConfirmingDelete = false

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
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          sectionLabel("Name")
          nameCard
          if isCreating {
            sectionLabel("Colour")
            colourCard
            sectionLabel("Icon")
            iconCard
          }
          if let errorMessage {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          if let category {
            deleteFooter(for: category)
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.xs)
      }
      .background(NomiColor.ground)
      .navigationTitle(isCreating ? "New Category" : "Edit Category")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel")
              .nomiTextStyle(.navAction)
              .foregroundStyle(NomiColor.navy)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            save()
          } label: {
            Text("Save")
              .nomiTextStyle(.navActionStrong)
              .foregroundStyle(NomiColor.navy)
          }
          .disabled(!canSave)
          .opacity(canSave ? 1 : 0.4)
        }
      }
      .alert(
        CategoryDeletion.alertTitle(for: category?.name ?? "category"),
        isPresented: $isConfirmingDelete
      ) {
        Button("Cancel", role: .cancel) {}
        Button("Delete", role: .destructive) { performDelete() }
      } message: {
        Text(CategoryDeletion.alertMessage)
      }
    }
    .nomiSheet(detents: [.large])
  }

  // MARK: - Fields

  private func sectionLabel(_ title: String) -> some View {
    Text(title)
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.dayHeader)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, NomiSpacing.sm)
      .padding(.bottom, NomiSpacing.xs)
      .padding(.horizontal, NomiSpacing.xxs)
      .accessibilityAddTraits(.isHeader)
  }

  private var nameCard: some View {
    TextField("Category name", text: $name)
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.ink)
      .accessibilityLabel("Name")
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
  }

  /// Seven swatches sharing the card's width, each with a 44 pt hit area. The
  /// filled circle is 28; the selected one gets a 2 pt ring just outside it.
  private var colourCard: some View {
    HStack(spacing: 0) {
      ForEach(PaletteSlotOptions.all, id: \.self) { slot in
        Button {
          selectedPaletteSlot = slot
        } label: {
          Circle()
            .fill(paletteSlot(slot))
            .frame(width: 28, height: 28)
            .overlay {
              if selectedPaletteSlot == slot {
                Circle()
                  .inset(by: -4)
                  .stroke(NomiColor.ink, lineWidth: 2)
              }
            }
            .frame(width: NomiSpacing.minTarget, height: NomiSpacing.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(PaletteSlotOptions.colourName(forSlot: slot))
        .accessibilityAddTraits(selectedPaletteSlot == slot ? .isSelected : [])
      }
    }
    .padding(.horizontal, 6)
    .frame(maxWidth: .infinity, minHeight: 52)
    .nomiCard(padding: EdgeInsets())
  }

  /// Eight icons in a four-column grid, 44 pt hit each. The selected icon sits
  /// on the `track` tile in navy.
  private var iconCard: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 6) {
      ForEach(PaletteSlotOptions.symbolChoices, id: \.self) { symbol in
        let isSelected = symbolName == symbol
        Button {
          symbolName = symbol
        } label: {
          Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: 22, height: 22)
            .foregroundStyle(isSelected ? NomiColor.navy : NomiColor.inkSecondary)
            .frame(width: NomiSpacing.minTarget, height: NomiSpacing.minTarget)
            .background(Circle().fill(isSelected ? NomiColor.track : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(PaletteSlotOptions.iconName(forSymbol: symbol))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(.vertical, 6)
    .padding(.horizontal, NomiSpacing.xs)
    .frame(maxWidth: .infinity)
    .nomiCard(padding: EdgeInsets())
  }

  /// The delete row for a deletable category, or the caption that says why
  /// there is none. `CategoryDeletion.isDeletable` decides which.
  @ViewBuilder
  private func deleteFooter(for category: NomiCore.Category) -> some View {
    if CategoryDeletion.isDeletable(category) {
      NomiDestructiveRow(title: "Delete category") {
        isConfirmingDelete = true
      }
      .padding(.horizontal, NomiSpacing.sm)
      .nomiCard(padding: EdgeInsets())
      .padding(.top, NomiSpacing.md)
    } else {
      Text("System category")
        .nomiTextStyle(.footnote)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(maxWidth: .infinity)
        .padding(.top, NomiSpacing.md)
    }
  }

  // MARK: - Actions

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

  private func performDelete() {
    guard let category, CategoryDeletion.isDeletable(category) else { return }
    do {
      try categoryStore.delete(category.id)
      dismiss()
    } catch {
      errorMessage = "Could not delete category."
    }
  }
}

#Preview("Category editor — create, light") {
  CategoryEditorSheet(categoryStore: FakeCategoryStore(), category: nil)
    .preferredColorScheme(.light)
}

#Preview("Category editor — custom category, light") {
  CategoryEditorSheet(categoryStore: FakeCategoryStore(), category: EntryRulesPreviewSupport.makeCategories()[2])
    .preferredColorScheme(.light)
}

#Preview("Category editor — system category, light") {
  CategoryEditorSheet(categoryStore: FakeCategoryStore(), category: EntryRulesPreviewSupport.makeCategories()[0])
    .preferredColorScheme(.light)
}
