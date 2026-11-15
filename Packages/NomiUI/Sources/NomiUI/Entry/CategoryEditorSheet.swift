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

/// v5: colour is one of the fixed seven-slot palette, never a free colour well
/// (§2.6). The editor no longer shows a colour row (S13): a saved category
/// keeps its slot, and a new one gets slot 0. These names stay the slot
/// vocabulary for the tests and the slot rule.
enum PaletteSlotOptions {
  static let all: [Int] = Array(CategoryPalette.slots.indices)

  /// The slot a category carries when it is saved. An edit writes back the slot
  /// it already has, a new category has none and gets 0, and a stored slot
  /// outside the seven falls back to 0. The editor can no longer change a slot,
  /// so keeping an out-of-range one would fail every save with a message the
  /// user cannot act on.
  static func slotOnSave(editing original: Int?) -> Int {
    guard let original, all.contains(original) else { return 0 }
    return original
  }

  /// VoiceOver names for the swatches, in `CategoryPalette.slots` order.
  static let slotNames = ["Orange", "Aqua", "Yellow", "Magenta", "Green", "Violet", "Red"]

  /// VoiceOver names for the icon grid, keyed by SF Symbol name. Every symbol in
  /// `CategoryEditorLogic.iconChoices` has one. A name says what the category
  /// is for, so the seeded symbols that repeat a plain one stay apart.
  static let symbolNames: [String: String] = [
    "fork.knife": "Food",
    "car.fill": "Ride",
    "bolt.fill": "Utilities",
    "house.fill": "Rent",
    "building.columns.fill": "Bank",
    "chart.line.uptrend.xyaxis": "Investments",
    "shield.fill": "Insurance",
    "banknote.fill": "Cash",
    "arrow.left.arrow.right": "Transfer",
    "bag.fill": "Shopping",
    "cart.fill": "Groceries",
    "cross.case.fill": "Health",
    "arrow.down.circle.fill": "Income",
    "tag": "Tag",
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
/// other form sheets do. Name and Icon are shown for both create and edit.
/// The colour row is hidden (S13): an edit keeps the slot the category has,
/// and a new category gets slot 0. `CategoryStore.update` still changes all
/// three fields in one write.
///
/// Every decision (what Save enables, the refusal under the name, the message
/// for a failed save, whether an edit changed anything, the delete footer) is
/// in `CategoryEditorLogic`. This view only draws them and runs the writes.
///
/// A non-system category ends with a "Delete category" row, pinned above the
/// bottom safe area, that asks first. A system category shows a "System
/// category" caption in that place. System categories can be renamed and
/// re-iconed; only delete is refused.
struct CategoryEditorSheet: View {
  let categoryStore: CategoryStore
  let category: NomiCore.Category?
  /// The names every other category holds, for the duplicate check. The
  /// category being edited is left out, so keeping its own name passes. Empty
  /// when the caller has no list to give, and then the store alone decides.
  let existingNames: [String]
  var onCreated: ((UUID) -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var draft: CategoryEditorLogic.Draft
  /// How the loaded category looked. Nil for a new category, which has no
  /// loaded state to differ from.
  private let original: CategoryEditorLogic.Draft?
  /// A failed save or delete. Cleared as soon as the user edits a field.
  @State private var errorMessage: String?
  @State private var isConfirmingDelete = false

  init(
    categoryStore: CategoryStore,
    category: NomiCore.Category?,
    existingNames: [String] = [],
    onCreated: ((UUID) -> Void)? = nil
  ) {
    self.categoryStore = categoryStore
    self.category = category
    self.existingNames = existingNames
    self.onCreated = onCreated
    let loaded = CategoryEditorLogic.Draft(
      name: category?.name ?? "",
      paletteSlot: PaletteSlotOptions.slotOnSave(editing: category?.paletteSlot),
      symbolName: category?.symbolName ?? PaletteSlotOptions.defaultSymbol
    )
    self.original = category == nil ? nil : loaded
    _draft = State(initialValue: loaded)
  }

  private var isCreating: Bool { category == nil }
  private var canSave: Bool {
    CategoryEditorLogic.canSave(draft, original: original, existingNames: existingNames)
  }
  /// The duplicate line while typing wins over an older save error.
  private var inlineMessage: String? {
    CategoryEditorLogic.nameMessage(for: draft, existingNames: existingNames) ?? errorMessage
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          sectionLabel("Name")
          nameCard
          if let inlineMessage {
            Text(inlineMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          sectionLabel("Icon")
          iconCard
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.xs)
      }
      .background(NomiColor.ground)
      .safeAreaInset(edge: .bottom) {
        if let category {
          bottomFooter(for: category)
        }
      }
      .onChange(of: draft) { _, _ in
        errorMessage = nil
      }
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
    TextField("Category name", text: $draft.name)
      .nomiTextStyle(.rowTitle)
      .foregroundStyle(NomiColor.ink)
      .accessibilityLabel("Name")
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
  }

  /// Every icon in a four-column grid, 44 pt hit each. The selected icon sits
  /// on the `track` tile in navy.
  private var iconCard: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 6) {
      ForEach(CategoryEditorLogic.iconChoices, id: \.self) { symbol in
        let isSelected = draft.symbolName == symbol
        Button {
          draft.symbolName = symbol
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

  /// The footer pinned to the bottom of a saved category's editor (D21): the
  /// Delete row, or the caption that says why there is none. The row is 16 pt
  /// above the bottom safe area. `CategoryEditorLogic.deleteFooter` decides
  /// which. The row draws its own card, so nothing wraps it here.
  @ViewBuilder
  private func bottomFooter(for category: NomiCore.Category) -> some View {
    VStack(spacing: 0) {
      switch CategoryEditorLogic.deleteFooter(for: category) {
      case .deleteRow:
        NomiDestructiveRow(title: "Delete category") {
          isConfirmingDelete = true
        }
      case .systemCaption:
        Text("System category")
          .nomiTextStyle(.footnote)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity)
      }
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
    .padding(.bottom, NomiSpacing.sm)
    .frame(maxWidth: .infinity)
    .background(NomiColor.ground)
  }

  // MARK: - Actions

  private func save() {
    guard canSave else { return }
    do {
      if let category {
        try categoryStore.update(
          category.id,
          name: draft.name,
          symbolName: draft.symbolName,
          paletteSlot: draft.paletteSlot
        )
        dismiss()
      } else {
        let created = try categoryStore.create(
          name: CategoryEditRules.normalizedName(draft.name),
          symbolName: draft.symbolName,
          paletteSlot: draft.paletteSlot
        )
        onCreated?(created.id)
        dismiss()
      }
    } catch {
      errorMessage = CategoryEditorLogic.saveMessage(for: error)
    }
  }

  private func performDelete() {
    guard let category, CategoryEditorLogic.mayDelete(category) else { return }
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
