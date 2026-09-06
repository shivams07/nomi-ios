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
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isAmountFocused: Bool

  @State private var amountText = ""
  @State private var direction: Direction = EntryDefaults.direction
  @State private var date = Date()
  @State private var categoryID: UUID?
  @State private var accountID: UUID?
  @State private var note = ""
  @State private var isCategoryPickerPresented = false
  @State private var isDatePickerPresented = false
  @State private var isAccountPickerPresented = false
  @State private var didPrefillCategory = false
  @State private var errorMessage: String?

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

  private var selectedAccount: NomiCore.Account? {
    accounts.first { $0.id == accountID }
  }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: NomiSpacing.lg) {
          amountField
          chipsRow
          DirectionToggle(direction: $direction)
          noteField
        }
        .padding(NomiSpacing.screenGutter)
      }
      .background(NomiColor.surfaceCanvas)
      .safeAreaInset(edge: .bottom) {
        savePill
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.bottom, NomiSpacing.sm)
          .background(NomiColor.surfaceCanvas)
      }
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
      accountID = EntryAccountDefault.preselection(from: accounts)
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: $categoryID)
    }
    .sheet(isPresented: $isDatePickerPresented) {
      DatePickerSheet(date: $date)
    }
    .sheet(isPresented: $isAccountPickerPresented) {
      // `accountStore: nil` — the entry sheet offers no inline account
      // creation; the picker's empty state points at the Accounts screen
      // instead (v2 amendment). Keeps `EntryView.init` unchanged.
      AccountPickerSheet(accountStore: nil, selection: accountID, onSelect: { accountID = $0 })
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
      presenting: errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  private var amountField: some View {
    HStack(spacing: NomiSpacing.xxs) {
      Text("₹")
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 39))
        .foregroundStyle(NomiColor.textPrimary)
      TextField("0", text: $amountText)
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
        .focused($isAmountFocused)
        .font(TabularFigures.font(name: NomiFont.montserratSemiBold, size: 39))
        .foregroundStyle(NomiColor.textPrimary)
        .onChange(of: amountText) { _, newValue in
          let sanitized = EntryAmount.sanitizeInput(newValue)
          if sanitized != newValue { amountText = sanitized }
        }
    }
    .padding(NomiSpacing.sm)
    .background(NomiColor.surfaceInput)
    .nomiCornerRadius(NomiRadius.tile)
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
      EntryChip(
        label: selectedAccount?.displayName ?? "Unassigned",
        leadingColor: nil,
        leadingSymbol: "creditcard",
        action: { isAccountPickerPresented = true }
      )
      Spacer(minLength: 0)
    }
  }

  private var noteField: some View {
    TextField("Note (optional)", text: $note)
      .nomiTextStyle(.body)
      .foregroundStyle(NomiColor.textPrimary)
      .padding(NomiSpacing.sm)
      .background(NomiColor.surfaceInput)
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
      categoryID: categoryID,
      accountID: accountID
    )
    do {
      _ = try transactionStore.add(draft)
      onSaved?()
      dismiss()
    } catch {
      // F8 (v3 amendment): a failed save used to be silently swallowed by
      // `try?`. Dismissing the alert is the only thing this does — neither
      // `onSaved?()` nor `dismiss()` ran, so the sheet stays open with every
      // typed field, including the draft, exactly as the user left it.
      errorMessage = "Could not save the transaction."
    }
  }
}

// M3: every preview's container now needs `NomiCore.Account` in its schema
// too, since `EntryView` `@Query`s it — `makeCategoryContainer(accounts:)`,
// not the original `makeCategoryContainer(seed:)`, which stays as it was
// for `CategoryEditorSheet`/`RulesScreen`.

#Preview("Entry — default, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .preferredColorScheme(.dark)
}

#Preview("Entry — accessibility 3, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.dark)
}

#Preview("Entry — no categories yet, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(categories: []))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(seed: [], accounts: []))
    .preferredColorScheme(.dark)
}

/// M3 done-when: "the chip 'Unassigned' with no accounts" is the three
/// previews above (none seed an account). This one is the counterpart: one
/// active account, so `EntryAccountDefault.preselection` picks it and the
/// chip shows it before Save, with no tap needed.
#Preview("Entry — account prefilled, dark") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(
      EntryRulesPreviewSupport.makeCategoryContainer(
        accounts: [NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4821")]
      )
    )
    .preferredColorScheme(.dark)
}
