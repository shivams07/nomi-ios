import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The Add transaction sheet (S5), drawn to the Add artboard. Spent, Income and
/// Transfer sit on one segmented control. The amount is the only required input
/// for Spent and Income, and a transfer also needs two different accounts. Under
/// the amount come the payee and category suggestions, then the account, date and
/// note rows. Save names what it will write and stays disabled until it can.
///
/// The rules live in `EntryModel` and the display in `EntryAmountDisplay`, so this
/// view only draws state and forwards taps. There is no custom keypad (DEC-14):
/// the system decimal pad is the amount keyboard.
///
/// `EntryView`'s public init is what RootView constructs, so it is unchanged.
public struct EntryView: View {
  public let transactionStore: TransactionStore
  public let categoryStore: CategoryStore
  public let onSaved: (() -> Void)?

  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  /// Created on appear, once the @Query lists have loaded. The lists are then
  /// kept in step with the store through `updateLists`.
  @State private var model: EntryModel?

  public init(transactionStore: TransactionStore, categoryStore: CategoryStore, onSaved: (() -> Void)? = nil) {
    self.transactionStore = transactionStore
    self.categoryStore = categoryStore
    self.onSaved = onSaved
  }

  private var accountOptions: [EntryAccountOption] {
    accounts.map { EntryAccountOption($0) }
  }

  private var categoryOptions: [EntryCategoryOption] {
    categories.map { EntryCategoryOption($0) }
  }

  public var body: some View {
    Group {
      if let model {
        EntryForm(model: model, categoryStore: categoryStore, onSaved: onSaved)
      }
    }
    .onAppear {
      guard model == nil else { return }
      model = EntryModel(
        store: EntryStoreWriter(transactionStore),
        accounts: accountOptions,
        categories: categoryOptions
      )
    }
    .onChange(of: accountOptions) { _, newValue in
      model?.updateLists(accounts: newValue, categories: categoryOptions)
    }
    .onChange(of: categoryOptions) { _, newValue in
      model?.updateLists(accounts: accountOptions, categories: newValue)
    }
  }
}

/// The sheet's content, bound to a model that already exists.
private struct EntryForm: View {
  @Bindable var model: EntryModel
  let categoryStore: CategoryStore
  let onSaved: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  /// The shell's import action (F3b). Nil in a preview, where no link is drawn.
  @Environment(\.nomiOpenImport) private var openImport
  @FocusState private var isAmountFocused: Bool

  @State private var isCategoryPickerPresented = false
  @State private var isDatePickerPresented = false
  @State private var accountField: AccountField?

  /// Which account row opened the picker. "Account" on a spent or income entry,
  /// "From" and "To" on a transfer.
  private enum AccountField: Hashable, Identifiable {
    case account
    case from
    case to

    var id: Self { self }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: NomiSpacing.cardGap) {
          kindControl
          amountCard
          if !model.isTransfer {
            payeeField
            suggestions
          }
          detailCard
        }
        .padding(.horizontal, NomiSpacing.screenGutter)
        .padding(.top, NomiSpacing.cardGap)
        .padding(.bottom, NomiSpacing.sm)
      }
      .background(NomiColor.ground)
      .safeAreaInset(edge: .bottom) {
        saveArea
      }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle("New transaction")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .nomiSheet(detents: [.large])
    .onAppear {
      isAmountFocused = true
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: $model.categoryID)
    }
    .sheet(isPresented: $isDatePickerPresented) {
      DatePickerSheet(date: $model.date)
    }
    .sheet(item: $accountField) { field in
      // `accountStore: nil`: the entry sheet offers no inline account creation.
      // The picker's empty state points at the Accounts screen instead.
      AccountPickerSheet(
        accountStore: nil,
        selection: selection(for: field),
        onSelect: { assign($0, to: field) }
      )
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      ),
      presenting: model.errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  // MARK: - Kind

  /// Capped at xxxLarge: NomiSegmented breaks a label mid-word at the
  /// Accessibility sizes ("Inco/me"), and its height is fixed. The kind is still
  /// named by the amount card's payee label and the save title at those sizes.
  private var kindControl: some View {
    NomiSegmented(kindOptions, selection: $model.kind, style: .onGround)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
  }

  private var kindOptions: [(value: EntryModel.Kind, title: String, systemImage: String?)] {
    model.availableKinds.map { kind -> (value: EntryModel.Kind, title: String, systemImage: String?) in
      (value: kind, title: Self.title(for: kind), systemImage: nil)
    }
  }

  private static func title(for kind: EntryModel.Kind) -> String {
    switch kind {
    case .spent: return "Spent"
    case .income: return "Income"
    case .transfer: return "Transfer"
    }
  }

  // MARK: - Amount

  /// The amount card: a centred "₹" and the amount, 46 pt. The typed digits are
  /// drawn by `amountDisplay`, laid over the field, and the field itself is drawn
  /// clear, so the caret and the keyboard still belong to the real text field.
  private var amountCard: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("₹")
        .font(amountFont)
        .foregroundStyle(NomiColor.ink)
        .accessibilityHidden(true)
      // The amount takes the row's width, never a fixed or intrinsic one, so the
      // whole amount stays on screen: `amountDisplay` shrinks to fit (the longest
      // valid amount is ₹1,00,00,00,000.00). The field sits over it, transparent,
      // and fills the same frame, so taps and the caret land on the real field.
      ZStack {
        amountDisplay
          .allowsHitTesting(false)
        TextField("", text: $model.amountText)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .accessibilityLabel("Amount")
          .focused($isAmountFocused)
          .font(amountFont)
          .multilineTextAlignment(.center)
          .foregroundStyle(.clear)
          .tint(NomiColor.ink)
      }
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, minHeight: 96)
    .padding(.horizontal, NomiSpacing.screenGutter)
    .entryCard(cornerRadius: 26)
  }

  private var amountFont: Font {
    NomiTextStyle.heroAmount.font
  }

  /// The drawn amount: the typed whole part in ink, the typed decimals dimmed, and
  /// a dimmed ".00" when no decimal separator has been typed. A "0" placeholder
  /// shows while the field is empty. VoiceOver reads the field, not this.
  /// One line, centred, shrunk to fit the row (`minimumScaleFactor`) and never
  /// truncated: the digits must all show at every Dynamic Type size.
  @ViewBuilder
  private var amountDisplay: some View {
    let display = model.amountDisplay
    if model.amountText.isEmpty {
      Text("0")
        .font(amountFont)
        .foregroundStyle(NomiColor.placeholder)
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(EntryAmountDisplay.minimumScaleFactor)
        .accessibilityHidden(true)
    } else {
      (Text(display.integer)
        .font(amountFont)
        .foregroundStyle(NomiColor.ink)
        + Text(display.typedDecimals + display.suffix)
        .font(amountFont)
        .foregroundStyle(NomiColor.ink.opacity(EntryAmountDisplay.decimalOpacity)))
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(EntryAmountDisplay.minimumScaleFactor)
        .accessibilityHidden(true)
    }
  }

  // MARK: - Payee and suggestions

  private var payeeLabel: String {
    model.kind == .income ? "Received from" : "Paid to"
  }

  /// The payee field, with the category's badge (the uncategorised badge until a
  /// category is chosen).
  private var payeeField: some View {
    let category = model.categoryOption(model.categoryID)
    return HStack(spacing: NomiSpacing.xs) {
      NomiCategoryBadge(
        symbolName: category?.symbolName ?? NomiCategoryBadge.uncategorisedSymbolName,
        paletteSlot: category?.paletteSlot,
        size: 28
      )
      .accessibilityHidden(true)
      TextField(payeeLabel, text: $model.payee)
        .font(.custom(NomiFont.interRegular, size: 16, relativeTo: .body))
        .foregroundStyle(NomiColor.ink)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    .entryCard(cornerRadius: 18)
  }

  /// The suggestion chips, then "More", which opens the category picker. A chosen
  /// category that is not among the suggestions is shown first, so the choice is
  /// never hidden behind "More".
  private var suggestions: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      if let heading = model.suggestionHeading {
        Text(heading)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .padding(.leading, 4)
      }
      EntryChipFlowLayout(spacing: NomiSpacing.xs) {
        if let chosen = model.categoryOption(model.categoryID),
          !model.visibleSuggestions.contains(where: { $0.id == chosen.id })
        {
          NomiChip(title: chosen.name, isSelected: true) {}
        }
        ForEach(model.visibleSuggestions, id: \.id) { option in
          NomiChip(title: option.name, isSelected: model.categoryID == option.id) {
            model.categoryID = option.id
          }
        }
        NomiChip(title: "More", isSelected: false) {
          isCategoryPickerPresented = true
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Detail rows

  /// The account rows (one, or From and To), the date, and the note. One card.
  private var detailCard: some View {
    VStack(spacing: 0) {
      if model.isTransfer {
        detailRow(
          "From",
          value: model.accountName(model.accountID),
          action: { accountField = .from }
        )
        detailRow(
          "To",
          value: model.accountName(model.toAccountID),
          action: { accountField = .to }
        )
      } else {
        detailRow(
          "Account",
          value: model.accountName(model.accountID),
          action: { accountField = .account }
        )
      }
      detailRow(
        "Date",
        value: dateText,
        action: { isDatePickerPresented = true }
      )
      noteRow
    }
    .nomiCard(padding: EdgeInsets())
  }

  private var dateText: String {
    Calendar.current.isDateInToday(model.date)
      ? "Today"
      : NomiFormatters.dayMonthYear.string(from: model.date)
  }

  /// A tappable row: the title, the value (or "Unassigned") and a chevron. Each row
  /// has a divider below it.
  private func detailRow(_ title: String, value: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xs) {
        // The title never breaks mid-word ("Accou/nt" at AX3); the value wraps instead.
        Text(title)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
          .fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: NomiSpacing.xs)
        Text(value ?? "Unassigned")
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(value == nil ? NomiColor.inkSecondary : NomiColor.ink)
          .multilineTextAlignment(.trailing)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
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
    .accessibilityLabel("\(title), \(value ?? "Unassigned")")
  }

  /// The note: the last row, with no divider. Its text is the note as typed.
  private var noteRow: some View {
    HStack(spacing: NomiSpacing.xs) {
      Text("Note")
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.ink)
      TextField("Optional", text: $model.note)
        .multilineTextAlignment(.trailing)
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
  }

  // MARK: - Accounts

  private func selection(for field: AccountField) -> UUID? {
    switch field {
    case .account, .from: return model.accountID
    case .to: return model.toAccountID
    }
  }

  private func assign(_ id: UUID?, to field: AccountField) {
    switch field {
    case .account, .from: model.accountID = id
    case .to: model.toAccountID = id
    }
  }

  // MARK: - Save

  /// The copy above the button says what is missing. The button names what it
  /// will write.
  private var saveArea: some View {
    VStack(spacing: NomiSpacing.xs) {
      if let caption = model.transferCaption {
        Text(caption)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
      }
      Button(action: save) {
        // One line, shrunk to fit the 54 pt button: "Save transfer of ₹…" wrapped
        // past the button at the Accessibility sizes (AX3 capture).
        Text(model.saveTitle)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: 54))
      .disabled(!model.canSave)
      if let openImport {
        // S5 follow-up. The one thing the link does is call the shell's import action.
        Button {
          EntryImportLink.activate(openImport)
        } label: {
          Text(EntryImportLink.title)
            .nomiTextStyle(.body)
            .foregroundStyle(NomiColor.primary)
            .underline()
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, NomiSpacing.screenGutter)
    .padding(.top, NomiSpacing.xs)
    .padding(.bottom, NomiSpacing.xs)
    .background(NomiColor.ground)
  }

  private func save() {
    guard model.save() else { return }
    onSaved?()
    dismiss()
  }
}

/// The "Import a bank statement instead" link under Save (the S5 follow-up, drawn
/// as the Add artboard's link). `activate` is all it does: it calls the shell's
/// import action once. A test passes a spy as the action.
enum EntryImportLink {
  static let title = "Import a bank statement instead"

  @MainActor
  static func activate(_ action: NomiShellAction?) {
    action?()
  }
}

#Preview("Add transaction · default · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .preferredColorScheme(.light)
}

#Preview("Add transaction · accessibility 3 · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(accounts: []))
    .environment(\.dynamicTypeSize, .accessibility3)
    .preferredColorScheme(.light)
}

#Preview("Add transaction · no categories yet · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore(categories: []))
    .modelContainer(EntryRulesPreviewSupport.makeCategoryContainer(seed: [], accounts: []))
    .preferredColorScheme(.light)
}

#Preview("Add transaction · two accounts, transfer ready · light") {
  EntryView(transactionStore: FakeTransactionStore(), categoryStore: FakeCategoryStore())
    .modelContainer(
      EntryRulesPreviewSupport.makeCategoryContainer(
        accounts: [
          NomiCore.Account(displayName: "HDFC Savings", institution: "HDFC Bank", lastFour: "4821"),
          NomiCore.Account(displayName: "ICICI", institution: "ICICI Bank", lastFour: "9012"),
        ]
      )
    )
    .preferredColorScheme(.light)
}
