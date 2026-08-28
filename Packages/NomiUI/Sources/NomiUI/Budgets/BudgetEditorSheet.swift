import NomiCore
import NomiPreview
import SwiftUI

/// Set-or-edit an amount for one category. Same amount-keypad idiom as U6's
/// `EntryView` — reuses `EntryAmount`'s parsing/sanitizing directly (both
/// files live in the same `NomiUI` target) rather than duplicating it, so the
/// two amount fields in the app can never drift on what counts as valid
/// input. Create/edit duality follows `RuleEditorSheet`: when `category` is
/// `nil` a `Picker` chooses among categories that don't have a budget yet;
/// when it's fixed, the category is a label, not a control.
struct BudgetEditorSheet: View {
  let budgetStore: BudgetStore
  let category: NomiCore.Category?
  let availableCategories: [NomiCore.Category]
  let currentAmountMinor: Int
  var onSaved: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @State private var amountText: String
  @State private var selectedCategoryID: UUID?
  @State private var errorMessage: String?

  init(
    budgetStore: BudgetStore,
    category: NomiCore.Category?,
    availableCategories: [NomiCore.Category],
    currentAmountMinor: Int,
    onSaved: (() -> Void)? = nil
  ) {
    self.budgetStore = budgetStore
    self.category = category
    self.availableCategories = availableCategories
    self.currentAmountMinor = currentAmountMinor
    self.onSaved = onSaved
    _amountText = State(initialValue: currentAmountMinor > 0 ? String(format: "%.2f", Double(currentAmountMinor) / 100) : "")
    _selectedCategoryID = State(initialValue: category?.id)
  }

  private var isCreating: Bool { category == nil }
  private var amountMinor: Int { EntryAmount.minorUnits(from: amountText) }
  private var canSave: Bool { BudgetFormGate.isValid(categoryID: selectedCategoryID) }
  private var intent: BudgetSaveIntent { BudgetSaveIntent.resolve(amountMinor: amountMinor) }

  var body: some View {
    NavigationStack {
      Form {
        if isCreating {
          Section("Category") {
            Picker("Category", selection: $selectedCategoryID) {
              ForEach(availableCategories) { option in
                Text(option.name).tag(Optional(option.id))
              }
            }
          }
        } else if let category {
          Section("Category") {
            Text(category.name)
              .nomiTextStyle(.body)
              .foregroundStyle(NomiColor.textPrimary)
          }
        }
        Section("Monthly Amount") {
          amountField
        }
        if intent == .remove {
          Section {
            Text("Setting the amount to ₹0 removes this budget.")
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.textTertiary)
          }
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
      .navigationTitle(isCreating ? "Add Budget" : "Edit Budget")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(intent == .remove && !isCreating ? "Remove" : "Save") { save() }
            .disabled(!canSave)
        }
      }
    }
  }

  private var amountField: some View {
    HStack(spacing: NomiSpacing.xxs) {
      Text("₹")
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 28))
        .foregroundStyle(NomiColor.textPrimary)
      TextField("0", text: $amountText)
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 28))
        .foregroundStyle(NomiColor.textPrimary)
        .onChange(of: amountText) { _, newValue in
          let sanitized = EntryAmount.sanitizeInput(newValue)
          if sanitized != newValue { amountText = sanitized }
        }
    }
  }

  private func save() {
    guard let categoryID = selectedCategoryID else { return }
    do {
      switch intent {
      case .remove:
        try budgetStore.removeBudget(categoryID: categoryID)
      case .set(let amount):
        try budgetStore.setBudget(categoryID: categoryID, amountMinor: amount)
      }
      onSaved?()
      dismiss()
    } catch {
      errorMessage = "Could not save this budget."
    }
  }
}

#Preview("Budget editor — create, dark") {
  BudgetEditorSheet(
    budgetStore: FakeBudgetStore(),
    category: nil,
    availableCategories: EntryRulesPreviewSupport.makeCategories(),
    currentAmountMinor: 0
  )
  .preferredColorScheme(.dark)
}

#Preview("Budget editor — edit existing, dark") {
  BudgetEditorSheet(
    budgetStore: FakeBudgetStore(),
    category: EntryRulesPreviewSupport.makeCategories().first,
    availableCategories: [],
    currentAmountMinor: 5000_00
  )
  .preferredColorScheme(.dark)
}
