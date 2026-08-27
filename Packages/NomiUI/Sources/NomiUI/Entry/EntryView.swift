import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The manual-entry sheet (U6). Done-when: the tap path from list to saved is
/// exactly two navigation/confirmation taps, amount is the only required
/// input, and no picker, segmented control or required field sits in that
/// path. Concretely: whoever presents this view spends tap one; the Save
/// pill below is tap two. Date, category and direction are all prefilled
/// with a sensible default and reachable only by an EXTRA, optional tap.
public struct EntryView: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore
  public let onSaved: (() -> Void)?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isAmountFocused: Bool

  @State private var amountText = ""
  @State private var direction: Direction = EntryDefaults.direction
  @State private var date = Date()
  @State private var categoryID: UUID?
  @State private var note = ""
  @State private var isCategoryPickerPresented = false
  @State private var isDatePickerPresented = false
  @State private var didPrefillCategory = false

  public init(transactionStore: TransactionStore, categoryStore: CategoryStore, onSaved: (() -> Void)? = nil) {
    self.transactionStore = transactionStore
    self.categoryStore = categoryStore
    self.onSaved = onSaved
  }

  private var amountMinor: Int { EntryAmount.minorUnits(from: amountText) }
  private var canSave: Bool { EntrySaveGate.isEnabled(amountMinor: amountMinor) }

  private var selectedCategory: NomiCore.Category? {
    categories.first { $0.id == categoryID }
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: NomiSpacing.lg) {
        amountField
        chipsRow
        DirectionToggle(direction: $direction)
        noteField
        Spacer()
        savePill
      }
      .padding(NomiSpacing.screenGutter)
      .background(NomiColor.surfaceCanvas)
      .navigationTitle("Add transaction")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .onAppear {
      isAmountFocused = true
      guard !didPrefillCategory else { return }
      didPrefillCategory = true
      categoryID = transactionStore.lastUsedCategoryID()
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: $categoryID)
    }
    .sheet(isPresented: $isDatePickerPresented) {
      DatePickerSheet(date: $date)
    }
  }

  private var amountField: some View {
    HStack(spacing: NomiSpacing.xxs) {
      Text("₹")
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 39))
        .foregroundStyle(NomiColor.textPrimary)
      TextField("0", text: $amountText)
        .keyboardType(.decimalPad)
        .focused($isAmountFocused)
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 39))
        .foregroundStyle(NomiColor.textPrimary)
        .onChange(of: amountText) { _, newValue in
          let sanitized = EntryAmount.sanitizeInput(newValue)
          if sanitized != newValue { amountText = sanitized }
        }
    }
  }

  private var chipsRow: some View {
    HStack(spacing: NomiSpacing.xs) {
      EntryChip(
        label: NomiFormatters.dayMonthYear.string(from: date),
        leadingColor: nil,
        leadingSymbol: "calendar",
        action: { isDatePickerPresented = true }
      )
      EntryChip(
        label: selectedCategory?.name ?? "Uncategorized",
        leadingColor: selectedCategory.map { paletteSlot($0.paletteSlot) },
        leadingSymbol: selectedCategory?.symbolName ?? "questionmark.circle",
        action: { isCategoryPickerPresented = true }
      )
      Spacer(minLength: 0)
    }
  }

  private var noteField: some View {
    TextField("Note (optional)", text: $note)
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.textPrimary)
      .padding(NomiSpacing.sm)
      .background(NomiColor.surface)
      .nomiCornerRadius(NomiRadius.tile)
  }

  private var savePill: some View {
    Button(action: save) {
      Text("Save")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, NomiSpacing.sm)
    }
    .background(canSave ? NomiColor.accent : NomiColor.accent.opacity(0.4))
    .nomiCornerRadius(NomiRadius.pill)
    .disabled(!canSave)
  }

  private func save() {
    guard canSave else { return }
    let draft = ManualTransactionDraft(
      date: date,
      amountMinor: amountMinor,
      descriptionText: note,
      direction: direction,
      categoryID: categoryID
    )
    guard (try? transactionStore.add(draft)) != nil else { return }
    onSaved?()
    dismiss()
  }
}

#Preview("Entry — default, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
    .preferredColorScheme(.dark)
}

#Preview("Entry — accessibility 3, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer())
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("Entry — no categories yet, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(categories: []))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(seed: []))
    .preferredColorScheme(.dark)
}
