import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The manual-entry sheet (U6), drawn to the approved Entry artboard (EN).
/// Done-when: the amount is the only required input; Expense / Income sits
/// directly under the amount; the chip row wraps (and stacks into full-width
/// rows at accessibility sizes); the note comes last; Save is pinned at 54 pt
/// and is disabled until the amount is positive. Date, category, account and
/// direction are prefilled and reachable only by an optional tap. There is no
/// custom keypad (DEC-14): the system decimal pad is the amount keyboard.
public struct EntryView: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore
  public let onSaved: (() -> Void)?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
        VStack(spacing: NomiSpacing.cardGap) {
          amountField
          DirectionToggle(direction: $direction)
          chips
          noteField
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.top, NomiSpacing.cardGap)
        .padding(.bottom, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      .safeAreaInset(edge: .bottom) {
        savePill
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.top, NomiSpacing.xs)
          .padding(.bottom, NomiSpacing.xs)
          .background(NomiColor.ground)
      }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("Add transaction")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .nomiSheet(detents: [.large])
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

  /// The amount card: a 96 pt card, the ₹ sign and a 39 pt field. The ₹ is
  /// decorative, so VoiceOver reads only the field.
  private var amountField: some View {
    HStack(spacing: 6) {
      Text("₹")
        .font(amountFont)
        .foregroundStyle(NomiColor.ink)
        .accessibilityHidden(true)
      TextField("Amount", text: $amountText, prompt: Text("0").foregroundStyle(NomiColor.placeholder))
        #if os(iOS)
        .keyboardType(.decimalPad)
        #endif
        .focused($isAmountFocused)
        .font(amountFont)
        .foregroundStyle(NomiColor.ink)
        .onChange(of: amountText) { _, newValue in
          let sanitized = EntryAmount.sanitizeInput(newValue)
          if sanitized != newValue { amountText = sanitized }
        }
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
    .entryCard(cornerRadius: 26)
  }

  private var amountFont: Font {
    .custom(NomiFont.interRegular, size: 39, relativeTo: .largeTitle).monospacedDigit()
  }

  /// Category, Account, Date, in that order. A wrapping flow row, or full-width
  /// rows at accessibility sizes.
  @ViewBuilder
  private var chips: some View {
    if dynamicTypeSize >= .accessibility1 {
      VStack(spacing: NomiSpacing.xs) {
        categoryChip
        accountChip
        dateChip
      }
    } else {
      EntryChipFlowLayout(spacing: NomiSpacing.xs) {
        categoryChip
        accountChip
        dateChip
      }
    }
  }

  private var categoryChip: some View {
    EntryChip(
      name: "Category",
      value: selectedCategory?.name ?? "Uncategorized",
      isPlaceholder: selectedCategory == nil,
      leadingColor: selectedCategory.map { paletteSlot($0.paletteSlot) },
      action: { isCategoryPickerPresented = true }
    )
  }

  private var accountChip: some View {
    EntryChip(
      name: "Account",
      value: selectedAccount?.displayName ?? "Unassigned",
      isPlaceholder: selectedAccount == nil,
      leadingColor: nil,
      action: { isAccountPickerPresented = true }
    )
  }

  private var dateChip: some View {
    EntryChip(
      name: "Date",
      value: Calendar.current.isDateInToday(date) ? "Today" : NomiFormatters.dayMonthYear.string(from: date),
      isPlaceholder: false,
      leadingColor: nil,
      action: { isDatePickerPresented = true }
    )
  }

  private var noteField: some View {
    // L4: this field writes `descriptionText`, not `Transaction.note` — the
    // detail screen's separate annotation — so its label says what it
    // actually captures rather than implying it's the note.
    TextField("What was it for? (optional)", text: $note, prompt: Text("What was it for? (optional)").foregroundStyle(NomiColor.placeholder))
      .font(.custom(NomiFont.interRegular, size: 16, relativeTo: .body))
      .foregroundStyle(NomiColor.ink)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .padding(.horizontal, 18)
      .entryCard(cornerRadius: 22)
  }

  private var savePill: some View {
    Button(action: save) {
      Text("Save")
    }
    .buttonStyle(NomiPrimaryButtonStyle(height: 54))
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

#Preview("Entry · default · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .preferredColorScheme(.light)
}

#Preview("Entry · accessibility 3 · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}

#Preview("Entry · no categories yet · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(categories: []))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(seed: [], accounts: []))
    .preferredColorScheme(.light)
}

/// M3 done-when: "the chip 'Unassigned' with no accounts" is the three
/// previews above (none seed an account). This one is the counterpart: one
/// active account, so `EntryAccountDefault.preselection` picks it and the
/// chip shows it before Save, with no tap needed.
#Preview("Entry · account prefilled · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(
      EntryRulesPreviewSupport.makeCategoryContainer(
        accounts: [NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4821")]
      )
    )
    .preferredColorScheme(.light)
}
