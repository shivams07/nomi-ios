import NomiCore
import NomiPreview
import SwiftUI

/// Set-or-edit a monthly amount for one category (BS, approved `BudgetEditor`
/// artboard). A medium form sheet: Cancel left, "Save" right (text, not a pill,
/// per SIMP §4 form sheets), a Category row, the "Monthly amount" field, and for
/// an existing budget a "Remove budget" row that asks first.
///
/// Amount parsing and sanitising are `EntryAmount`'s, so the two amount fields
/// in the app agree on what counts as valid input. Create/edit duality follows
/// `RuleEditorSheet`: when `category` is `nil` a picker chooses among categories
/// without a budget; when it is fixed, the category is a label, not a control.
struct BudgetEditorSheet: View {
  let budgetStore: BudgetStore
  let category: NomiCore.Category?
  let availableCategories: [NomiCore.Category]
  let currentAmountMinor: Int
  var onSaved: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  /// The sheet's state and actions (T2a). See `BudgetEditorModel`.
  @State private var model: BudgetEditorModel

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
    _model = State(
      initialValue: BudgetEditorModel(
        store: budgetStore, category: category, currentAmountMinor: currentAmountMinor))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          sectionLabel("Category")
          categoryCard
          sectionLabel("Monthly amount")
          amountCard
          if let hint = BudgetAmountHint.text(for: model.amountText) {
            Text(hint)
              .nomiTextStyle(.footnote)
              .foregroundStyle(NomiColor.inkSecondary)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          if let errorMessage = model.errorMessage {
            Text(errorMessage)
              .nomiTextStyle(.caption)
              .foregroundStyle(NomiColor.error)
              .padding(.top, NomiSpacing.xs)
              .padding(.horizontal, NomiSpacing.xxs)
          }
          if model.isExistingBudget {
            NomiDestructiveRow(title: "Remove budget") {
              model.requestRemove()
            }
            .padding(.top, NomiSpacing.sm)
          }
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.vertical, NomiSpacing.xs)
      }
      .background(NomiColor.ground)
      .navigationTitle(model.isCreating ? "Add Budget" : "Edit Budget")
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
            if model.save() {
              onSaved?()
              dismiss()
            }
          } label: {
            Text("Save")
              .nomiTextStyle(.navActionStrong)
              .foregroundStyle(NomiColor.navy)
          }
          .disabled(!model.canSave)
          .opacity(model.canSave ? 1 : 0.4)
        }
      }
      .alert("Remove this budget?", isPresented: $model.isConfirmingRemove) {
        Button("Remove", role: .destructive) {
          if model.confirmRemove() {
            onSaved?()
            dismiss()
          }
        }
        Button("Cancel", role: .cancel) { model.cancelRemove() }
      } message: {
        Text(BudgetRemoveConfirmation.message(categoryName: category?.name ?? ""))
      }
    }
    .nomiSheet(detents: [.medium])
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

  /// One 56 pt card row holding a field: the same chrome for the category and
  /// the amount.
  private func fieldCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
  }

  @ViewBuilder
  private var categoryCard: some View {
    if model.isCreating {
      fieldCard {
        Picker("Category", selection: $model.selectedCategoryID) {
          Text("Choose a category").tag(nil as UUID?)
          ForEach(availableCategories) { option in
            Text(option.name).tag(Optional(option.id))
          }
        }
        .pickerStyle(.menu)
        .tint(NomiColor.navy)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      }
    } else if let category {
      fieldCard {
        HStack(spacing: NomiSpacing.sm) {
          NomiCategoryBadge(symbolName: category.symbolName, paletteSlot: category.paletteSlot, size: 32)
          Text(category.name)
            .nomiTextStyle(.rowTitle)
            .foregroundStyle(NomiColor.ink)
          Spacer(minLength: 0)
        }
      }
    }
  }

  private var amountCard: some View {
    fieldCard {
      HStack(spacing: NomiSpacing.xs) {
        Text("₹")
          .font(TabularFigures.font(name: NomiFont.interSemiBold, size: 24))
          .foregroundStyle(NomiColor.ink)
        TextField("0", text: $model.amountText)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .font(TabularFigures.font(name: NomiFont.interSemiBold, size: 24))
          .foregroundStyle(NomiColor.ink)
          .accessibilityLabel("Monthly amount")
          .onChange(of: model.amountText) { _, newValue in
            model.amountDidChange(newValue)
          }
      }
    }
  }
}

#Preview("Budget editor — create") {
  BudgetEditorSheet(
    budgetStore: FakeBudgetStore(),
    category: nil,
    availableCategories: EntryRulesPreviewSupport.makeCategories(),
    currentAmountMinor: 0
  )
  .preferredColorScheme(.light)
}

#Preview("Budget editor — edit existing") {
  BudgetEditorSheet(
    budgetStore: FakeBudgetStore(),
    category: EntryRulesPreviewSupport.makeCategories().first,
    availableCategories: [],
    currentAmountMinor: 5000_00
  )
  .preferredColorScheme(.light)
}

/// `.constant(true)` presentation, same idiom as `LedgerScreen`'s
/// confirmation-dialog previews. It shows the `.medium` detent and radius atop
/// a real background, not the bare form.
#Preview("Budget editor — presented as a sheet") {
  NomiColor.ground
    .sheet(isPresented: .constant(true)) {
      BudgetEditorSheet(
        budgetStore: FakeBudgetStore(),
        category: EntryRulesPreviewSupport.makeCategories().first,
        availableCategories: [],
        currentAmountMinor: 5000_00
      )
    }
    .preferredColorScheme(.light)
}
