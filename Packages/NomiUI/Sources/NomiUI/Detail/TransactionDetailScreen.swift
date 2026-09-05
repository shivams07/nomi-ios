import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

/// The transaction detail screen (fix-plan unit 1). Pushed from `LedgerScreen`
/// via `NavigationLink(value: transaction.id)` / `.navigationDestination(for:
/// UUID.self)`, so it takes an id rather than the row itself and reads the row,
/// categories and accounts back out through `@Query` — the container reaches
/// it because it is pushed inside the Ledger tab's own `NavigationStack`.
///
/// Closes three dead ends the review queue had no exit from: assigning a
/// category or account to *any* row (not just ones a rule already touched),
/// editing amount/date/description — the only path off a review-queue ₹0 row
/// nothing could parse — and deleting a mis-imported row with a confirmation
/// in front of it. No store call here uses `try?`: every failure surfaces in
/// an `.alert`, a deliberate departure from `AccountRenameSheet`/
/// `RuleEditorSheet`'s inline error text, because this screen can fail in more
/// places (four independent store calls, not one) and a swallowed failure here
/// means the user thinks their edit or delete took effect when it didn't.
public struct TransactionDetailScreen: View {
  public let transactionID: UUID
  public let transactionStore: TransactionStore
  public let editor: TransactionEditing
  public let categoryStore: CategoryStore
  public let accountStore: AccountStore

  @Query private var matches: [NomiCore.Transaction]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  @Environment(\.dismiss) private var dismiss

  @State private var pendingCategorySelection: UUID?
  @State private var isCategoryPickerPresented = false
  @State private var isAccountPickerPresented = false
  @State private var isDatePickerPresented = false
  @State private var isConfirmingDelete = false
  @State private var errorMessage: String?

  @State private var amountText = ""
  @State private var editedDate = Date()
  @State private var editedDescription = ""
  @State private var didPrefillEdit = false

  public init(
    transactionID: UUID,
    transactionStore: TransactionStore,
    editor: TransactionEditing,
    categoryStore: CategoryStore,
    accountStore: AccountStore
  ) {
    self.transactionID = transactionID
    self.transactionStore = transactionStore
    self.editor = editor
    self.categoryStore = categoryStore
    self.accountStore = accountStore
    _matches = Query(filter: #Predicate<NomiCore.Transaction> { $0.id == transactionID })
  }

  private var transaction: NomiCore.Transaction? { matches.first }

  private var editedAmountMinor: Int { EntryAmount.minorUnits(from: amountText) }
  private var canSaveEdit: Bool { EntrySaveGate.isEnabled(amountMinor: editedAmountMinor) }

  public var body: some View {
    Group {
      if let transaction {
        List {
          headerSection(transaction)
          categorySection(transaction)
          accountSection(transaction)
          editSection
          sourceSection(transaction)
          if TransactionDetailLogic.availableActions(needsReview: transaction.needsReview).contains(.markReviewed) {
            Section {
              Button("Mark reviewed") { markReviewed() }
            }
            .listRowBackground(NomiColor.surfaceRaised)
          }
          Section {
            Button("Delete", role: .destructive) { isConfirmingDelete = true }
          }
          .listRowBackground(NomiColor.surfaceRaised)
        }
        .scrollContentBackground(.hidden)
        .background(NomiColor.surfaceCanvas)
        .onAppear { prefillEditIfNeeded(transaction) }
      } else {
        // Reached for a beat after `delete()` pops this screen — the `@Query`
        // above updates before the pop animation finishes — and, defensively,
        // for an id that no longer matches any row.
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(NomiColor.surfaceCanvas)
      }
    }
    .navigationTitle("Transaction")
    .confirmationDialog(
      "Delete this transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { performDelete() }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: $pendingCategorySelection)
    }
    .sheet(isPresented: $isAccountPickerPresented) {
      AccountPickerSheet(accountStore: accountStore, selection: transaction?.accountID) { newAccountID in
        updateAccount(to: newAccountID)
      }
    }
    .sheet(isPresented: $isDatePickerPresented) {
      DatePickerSheet(date: $editedDate)
    }
    .onChange(of: pendingCategorySelection) { _, newValue in
      guard let newValue else { return }
      updateCategory(to: newValue)
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
      presenting: errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  // MARK: - Header

  private func headerSection(_ transaction: NomiCore.Transaction) -> some View {
    Section {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(transaction.merchantName ?? transaction.descriptionText)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
        Text(TransactionRow.amountText(minor: transaction.amountMinor, direction: transaction.direction))
          .font(TabularFigures.font(name: NomiFont.montserratMedium, size: 20))
          .foregroundStyle(transaction.direction == .credit ? NomiColor.creditText : NomiColor.debitText)
        Text(NomiFormatters.dayMonthYear.string(from: transaction.date))
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textTertiary)
        ForEach(
          TransactionDetailLogic.flagReasons(
            accountID: transaction.accountID, needsReview: transaction.needsReview,
            mergedCount: transaction.mergedCount
          ), id: \.self
        ) { reason in
          Text(reason)
            .nomiTextStyle(.caption)
            .foregroundStyle(CategoryPalette.other)
        }
      }
      .padding(.vertical, NomiSpacing.xxs)
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  // MARK: - Category / Account

  private func categorySection(_ transaction: NomiCore.Transaction) -> some View {
    Section("Category") {
      let name = transaction.categoryID.flatMap { id in categories.first { $0.id == id }?.name } ?? "Uncategorized"
      Button {
        pendingCategorySelection = transaction.categoryID
        isCategoryPickerPresented = true
      } label: {
        HStack {
          Text(name).foregroundStyle(NomiColor.textPrimary)
          Spacer()
          Image(systemName: "chevron.right").foregroundStyle(NomiColor.textTertiary)
        }
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  private func accountSection(_ transaction: NomiCore.Transaction) -> some View {
    Section("Account") {
      let name = transaction.accountID.flatMap { id in accounts.first { $0.id == id }?.displayName } ?? "Unassigned"
      Button {
        isAccountPickerPresented = true
      } label: {
        HStack {
          Text(name).foregroundStyle(NomiColor.textPrimary)
          Spacer()
          Image(systemName: "chevron.right").foregroundStyle(NomiColor.textTertiary)
        }
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  // MARK: - Edit

  private var editSection: some View {
    Section("Edit") {
      HStack(spacing: NomiSpacing.xxs) {
        Text("₹").foregroundStyle(NomiColor.textPrimary)
        TextField("0", text: $amountText)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .onChange(of: amountText) { _, newValue in
            let sanitized = EntryAmount.sanitizeInput(newValue)
            if sanitized != newValue { amountText = sanitized }
          }
      }
      Button {
        isDatePickerPresented = true
      } label: {
        HStack {
          Text("Date").foregroundStyle(NomiColor.textPrimary)
          Spacer()
          Text(NomiFormatters.dayMonthYear.string(from: editedDate))
            .foregroundStyle(NomiColor.textTertiary)
        }
      }
      TextField("Description", text: $editedDescription)
      Button("Save changes") { saveEdit() }
        .disabled(!canSaveEdit)
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  // MARK: - Source

  private func sourceSection(_ transaction: NomiCore.Transaction) -> some View {
    Section("Source") {
      Text(transaction.source.rawValue.capitalized)
        .foregroundStyle(NomiColor.textPrimary)
      ForEach(TransactionDetailLogic.sourceSummary(refs: transaction.sourceRefs), id: \.self) { line in
        Text(line)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(NomiColor.textTertiary)
      }
      Text("Merged from \(transaction.mergedCount) source\(transaction.mergedCount == 1 ? "" : "s")")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      Text(transaction.descriptionText)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(NomiColor.textSecondary)
      if let merchantName = transaction.merchantName {
        Text("Merchant: \(merchantName)").nomiTextStyle(.caption).foregroundStyle(NomiColor.textTertiary)
      }
      if let counterpartyVPA = transaction.counterpartyVPA {
        Text("VPA: \(counterpartyVPA)").nomiTextStyle(.caption).foregroundStyle(NomiColor.textTertiary)
      }
      if let upiKindRaw = transaction.upiKindRaw {
        Text("UPI: \(upiKindRaw)").nomiTextStyle(.caption).foregroundStyle(NomiColor.textTertiary)
      }
    }
    .listRowBackground(NomiColor.surfaceRaised)
  }

  // MARK: - Actions

  private func prefillEditIfNeeded(_ transaction: NomiCore.Transaction) {
    guard !didPrefillEdit else { return }
    didPrefillEdit = true
    amountText = String(format: "%.2f", Double(transaction.amountMinor) / 100)
    editedDate = transaction.date
    editedDescription = transaction.descriptionText
  }

  private func updateCategory(to categoryID: UUID) {
    do {
      try transactionStore.setCategory(transactionID, to: categoryID)
    } catch {
      errorMessage = "Could not update the category."
    }
  }

  private func updateAccount(to accountID: UUID?) {
    do {
      try transactionStore.setAccount(transactionID, to: accountID)
    } catch {
      errorMessage = "Could not update the account."
    }
  }

  private func saveEdit() {
    guard canSaveEdit else { return }
    do {
      try editor.update(
        transactionID, amountMinor: editedAmountMinor, date: editedDate, descriptionText: editedDescription)
    } catch {
      errorMessage = "Could not save the changes."
    }
  }

  private func markReviewed() {
    do {
      try transactionStore.dismissReview(transactionID)
    } catch {
      errorMessage = "Could not mark this reviewed."
    }
  }

  private func performDelete() {
    do {
      try transactionStore.delete(transactionID)
      dismiss()
    } catch {
      errorMessage = "Could not delete this transaction."
    }
  }
}

// MARK: - Previews

/// A manual-source fixture: `PreviewData.transactions` has no manual row, and
/// the "manual row" preview the done-when asks for needs one. Added to both a
/// fake store and the container seed with the identical instance, same
/// convention as `LedgerPreviewSupport`'s custom fixtures.
private enum TransactionDetailPreviewFixtures {
  static let manual: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -3 * 86400)
    let description = "Cash withdrawal"
    let normalized = normalizeDescription(description)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
      date: date,
      descriptionText: description,
      normalizedDescription: normalized,
      amountMinor: 200_00,
      directionRaw: Direction.debit.rawValue,
      categoryID: PreviewData.categories[0].id,
      categorySourceRaw: CategorySource.manual.rawValue,
      accountID: PreviewData.accounts[0].id,
      sourceRaw: IngestSource.manual.rawValue,
      sourceRefs: [SourceRef(source: .manual, externalID: UUID().uuidString, capturedAt: date)],
      dedupeKey: makeDedupeKey(
        date: date, amountMinor: 200_00, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
      ),
      createdAt: date,
      updatedAt: date
    )
  }()
}

#Preview("Transaction detail — flagged email row, dark") {
  let transaction = PreviewData.transactions.first { $0.needsReview }!
  NavigationStack {
    TransactionDetailScreen(
      transactionID: transaction.id,
      transactionStore: FakeTransactionStore(),
      editor: FakeTransactionEditor(),
      categoryStore: FakeCategoryStore(),
      accountStore: FakeAccountStore()
    )
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — merged row, dark") {
  let transaction = PreviewData.transactions.first { $0.mergedCount > 1 }!
  NavigationStack {
    TransactionDetailScreen(
      transactionID: transaction.id,
      transactionStore: FakeTransactionStore(),
      editor: FakeTransactionEditor(),
      categoryStore: FakeCategoryStore(),
      accountStore: FakeAccountStore()
    )
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — manual row, dark") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.manual]
  NavigationStack {
    TransactionDetailScreen(
      transactionID: TransactionDetailPreviewFixtures.manual.id,
      transactionStore: FakeTransactionStore(transactions: transactions),
      editor: FakeTransactionEditor(transactions: transactions),
      categoryStore: FakeCategoryStore(),
      accountStore: FakeAccountStore()
    )
  }
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — accessibility 3, dark") {
  let transaction = PreviewData.transactions.first { $0.mergedCount == 1 && !$0.needsReview }!
  NavigationStack {
    TransactionDetailScreen(
      transactionID: transaction.id,
      transactionStore: FakeTransactionStore(),
      editor: FakeTransactionEditor(),
      categoryStore: FakeCategoryStore(),
      accountStore: FakeAccountStore()
    )
  }
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
