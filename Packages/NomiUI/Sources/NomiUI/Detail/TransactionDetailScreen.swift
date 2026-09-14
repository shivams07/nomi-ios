import Foundation
import NomiCore
import NomiPreview
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// `LedgerScreen`'s `.sheet(item:)` identity — a bare `UUID` isn't
/// `Identifiable`, and wrapping it here (rather than conforming `UUID`
/// itself, which this module doesn't own) keeps the presentation type
/// specific to this one sheet.
public struct PresentedTransaction: Identifiable, Hashable, Sendable {
  public let id: UUID

  public init(id: UUID) {
    self.id = id
  }
}

/// The transaction detail screen. v5 (`nomi-ui-refresh`, M4): presented as
/// the shared bottom-sheet style from `LedgerScreen` (`.sheet(item:)`,
/// `PresentedTransaction`), not pushed — it takes an id rather than the row
/// itself and reads the row, categories and accounts back out through
/// `@Query`; `.sheet(item:)` applies its own `.modelContainer` (see
/// `LedgerScreen`'s note), which is what makes that `@Query` safe here.
///
/// Closes three dead ends the review queue had no exit from: assigning a
/// category or account to *any* row (not just ones a rule already touched),
/// editing amount/date/description — the only path off a review-queue ₹0 row
/// nothing could parse — and deleting a mis-imported row with a confirmation
/// in front of it. No store call here uses `try?`: every failure surfaces in
/// an `.alert`, a deliberate departure from `AccountRenameSheet`/
/// `RuleEditorSheet`'s inline error text, because this screen can fail in more
/// places (four independent store calls, not one) and a swallowed failure here
/// means the user thinks their edit or delete took effect when it didn't. The
/// one deliberate exception is the suggestion read below.
public struct TransactionDetailScreen: View {
  public let transactionID: UUID
  public let transactionStore: TransactionStore
  public let editor: TransactionEditing
  public let categoryStore: CategoryStore
  public let accountStore: AccountStore
  public let suggester: (any CategorySuggesting)?

  @Query private var matches: [NomiCore.Transaction]
  @Query(sort: \NomiCore.Category.sortIndex) private var categories: [NomiCore.Category]
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  @Environment(\.dismiss) private var dismiss

  @State private var pendingCategorySelection: UUID?
  @State private var isCategoryPickerPresented = false
  @State private var isAccountPickerPresented = false
  @State private var isDatePickerPresented = false
  @State private var isConfirmingDelete = false
  @State private var isEditExpanded = false
  @State private var errorMessage: String?
  @State private var suggestion: CategorySuggestion?

  @State private var amountText = ""
  @State private var editedDate = Date()
  @State private var editedDescription = ""
  @State private var editedNote = ""
  @State private var didPrefillEdit = false

  public init(
    transactionID: UUID,
    transactionStore: TransactionStore,
    editor: TransactionEditing,
    categoryStore: CategoryStore,
    accountStore: AccountStore,
    suggester: (any CategorySuggesting)? = nil
  ) {
    self.transactionID = transactionID
    self.transactionStore = transactionStore
    self.editor = editor
    self.categoryStore = categoryStore
    self.accountStore = accountStore
    self.suggester = suggester
    _matches = Query(filter: #Predicate<NomiCore.Transaction> { $0.id == transactionID })
  }

  private var transaction: NomiCore.Transaction? { matches.first }

  private var editedAmountMinor: Int { EntryAmount.minorUnits(from: amountText) }
  private var canSaveEdit: Bool { EntrySaveGate.isEnabled(amountMinor: editedAmountMinor) }

  /// U18: the edit field's leading glyph is the row's own currency symbol,
  /// not a hardcoded "₹" — a USD row edits in `$`, not rupees. `en_IN` stays
  /// the locale (same reasoning as `NomiFormatters.amountString`); only the
  /// symbol is read off the formatter, the amount text field carries the
  /// digits.
  private var currencySymbol: String {
    guard let currencyCode = transaction?.currencyCode, currencyCode != "INR" else { return "₹" }
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.numberStyle = .currency
    formatter.currencyCode = currencyCode
    return formatter.currencySymbol
  }

  private func categoryName(for transaction: NomiCore.Transaction) -> String? {
    transaction.categoryID.flatMap { id in categories.first { $0.id == id }?.name }
  }

  private func isSuggestionShown(for transaction: NomiCore.Transaction) -> Bool {
    SuggestionRow.isShown(
      suggestion: suggestion, currentCategoryID: transaction.categoryID, categorySource: transaction.categorySource)
  }

  public var body: some View {
    Group {
      if let transaction {
        ScrollView {
          VStack(spacing: NomiSpacing.md) {
            topRow
            headerSection(transaction)
            if isSuggestionShown(for: transaction), let suggestion {
              suggestionPanel(transaction: transaction, suggestion: suggestion)
            }
            rowsSection(transaction, suggestionShown: isSuggestionShown(for: transaction))
            if TransactionDetailLogic.availableActions(needsReview: transaction.needsReview).contains(.markReviewed) {
              markReviewedRow
            }
            if isEditExpanded {
              editSection
              sourceSection(transaction)
              if transaction.upiKindRaw != nil {
                upiSection(transaction)
              }
            }
          }
          .padding(NomiSpacing.screenGutter)
        }
        .onAppear {
          prefillEditIfNeeded(transaction)
          refreshSuggestion()
        }
      } else {
        // Reached for a beat after `delete()` dismisses this sheet — the
        // `@Query` above updates before the dismiss animation finishes — and,
        // defensively, for an id that no longer matches any row.
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(NomiColor.surfaceCanvas)
      }
    }
    .background(NomiColor.surfaceCanvas)
    .nomiSheet()
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

  // MARK: - Top row

  private var topRow: some View {
    HStack {
      circleButton(systemName: "xmark") { dismiss() }
      Spacer()
      circleButton(systemName: "pencil") { isEditExpanded.toggle() }
      circleButton(systemName: "trash") { isConfirmingDelete = true }
    }
  }

  private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .foregroundStyle(NomiColor.textSecondary)
        .frame(width: 32, height: 32)
        .background(NomiColor.glassFill)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Header

  private func headerSection(_ transaction: NomiCore.Transaction) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      let category = transaction.categoryID.flatMap { id in categories.first { $0.id == id } }
      NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 56)
      Text(
        TransactionRow.title(
          merchantName: transaction.merchantName, descriptionText: transaction.descriptionText,
          categoryName: categoryName(for: transaction))
      )
        .nomiTextStyle(.title)
        .foregroundStyle(NomiColor.textPrimary)
      Text(
        TransactionRow.amountText(
          minor: transaction.amountMinor, direction: transaction.direction, currencyCode: transaction.currencyCode)
      )
        .nomiTextStyle(.displayValue)
        .foregroundStyle(transaction.direction == .credit ? NomiColor.creditText : NomiColor.debitText)
      // U24: shown only when present — a note is a fact about the row, not a
      // flag, so it sits with the header rather than in `flagReasons`.
      if let note = transaction.note {
        Text(note)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.textSecondary)
      }
      ForEach(
        TransactionDetailLogic.flagReasons(
          accountID: transaction.accountID, needsReview: transaction.needsReview, mergedCount: transaction.mergedCount
        ), id: \.self
      ) { reason in
        Text(reason)
          .nomiTextStyle(.caption)
          .foregroundStyle(CategoryPalette.other)
      }
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }

  // MARK: - Suggestion panel

  private func suggestionPanel(transaction: NomiCore.Transaction, suggestion: CategorySuggestion) -> some View {
    let category = categories.first { $0.id == suggestion.categoryID }
    let categoryName = category?.name ?? "Uncategorized"
    let merchantLabel = transaction.merchantName ?? transaction.descriptionText
    return VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Text("✦ Suggested category")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      HStack(spacing: NomiSpacing.xs) {
        NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 32)
        Text(categoryName)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.textPrimary)
      }
      Text(SuggestionRow.reasonText(reason: suggestion.reason, merchantLabel: merchantLabel, categoryName: categoryName))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      HStack(spacing: NomiSpacing.xs) {
        pillButton(title: "Change category", background: NomiColor.surface) {
          pendingCategorySelection = transaction.categoryID
          isCategoryPickerPresented = true
        }
        pillButton(title: "Apply", background: NomiColor.accent) {
          updateCategory(to: suggestion.categoryID)
        }
      }
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRow)
    .overlay(
      RoundedRectangle(cornerRadius: NomiRadius.inset, style: NomiRadius.cardSheetStyle)
        .stroke(NomiColor.glassHairline, lineWidth: 1)
    )
    .nomiCornerRadius(NomiRadius.inset)
  }

  private func pillButton(title: String, background: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .nomiTextStyle(.body)
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, NomiSpacing.xs)
        .background(background)
        .clipShape(Capsule(style: .continuous))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Rows

  private func rowsSection(_ transaction: NomiCore.Transaction, suggestionShown: Bool) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      // Hidden while the suggestion panel shows — the panel already carries
      // the category badge and name.
      if !suggestionShown {
        categoryRow(transaction)
      }
      accountRow(transaction)
      dateRow
    }
  }

  private func detailRow<Content: View>(action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
    Button(action: action) {
      content()
        .padding(NomiSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NomiColor.surfaceRow)
        .nomiCornerRadius(NomiRadius.inset)
    }
    .buttonStyle(.plain)
  }

  private func categoryRow(_ transaction: NomiCore.Transaction) -> some View {
    let category = transaction.categoryID.flatMap { id in categories.first { $0.id == id } }
    return detailRow {
      pendingCategorySelection = transaction.categoryID
      isCategoryPickerPresented = true
    } content: {
      HStack(spacing: NomiSpacing.xs) {
        NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 32)
        Text(category?.name ?? "Uncategorized")
          .foregroundStyle(NomiColor.textPrimary)
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  private func accountRow(_ transaction: NomiCore.Transaction) -> some View {
    let name = transaction.accountID.flatMap { id in accounts.first { $0.id == id }?.displayName } ?? "Unassigned"
    return detailRow {
      isAccountPickerPresented = true
    } content: {
      HStack {
        Text(name).foregroundStyle(NomiColor.textPrimary)
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  /// Opening the date picker also expands the edit section — that's where
  /// "Save changes" lives, and there is no other way to commit a date pick.
  private var dateRow: some View {
    detailRow {
      isEditExpanded = true
      isDatePickerPresented = true
    } content: {
      HStack {
        Image(systemName: "calendar").foregroundStyle(NomiColor.textSecondary)
        Spacer()
        Text(NomiFormatters.dayMonthYear.string(from: editedDate))
          .foregroundStyle(NomiColor.textTertiary)
      }
    }
  }

  private var markReviewedRow: some View {
    Button("Mark reviewed") { markReviewed() }
      .foregroundStyle(NomiColor.textPrimary)
      .frame(maxWidth: .infinity)
      .padding(NomiSpacing.cardPadding)
      .background(NomiColor.surfaceRow)
      .nomiCornerRadius(NomiRadius.inset)
  }

  // MARK: - Edit (pencil-toggled)

  private var editSection: some View {
    VStack(alignment: .leading, spacing: NomiSpacing.sm) {
      HStack(spacing: NomiSpacing.xxs) {
        Text(currencySymbol).foregroundStyle(NomiColor.textPrimary)
        TextField("0", text: $amountText)
          #if os(iOS)
          .keyboardType(.decimalPad)
          #endif
          .onChange(of: amountText) { _, newValue in
            let sanitized = EntryAmount.sanitizeInput(newValue)
            if sanitized != newValue { amountText = sanitized }
          }
      }
      TextField("Description", text: $editedDescription)
      TextField("Note", text: $editedNote)
      Button("Save changes") { saveEdit() }
        .disabled(!canSaveEdit)
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRow)
    .nomiCornerRadius(NomiRadius.inset)
  }

  // MARK: - Source

  private func sourceSection(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("Source")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
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
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRow)
    .nomiCornerRadius(NomiRadius.inset)
  }

  // MARK: - UPI

  private func upiSection(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("UPI")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.textTertiary)
      if let kindRaw = transaction.upiKindRaw {
        Text(UPIDisplay.kindLabel(kindRaw) ?? kindRaw.capitalized)
          .foregroundStyle(NomiColor.textPrimary)
      }
      if let vpa = transaction.counterpartyVPA {
        HStack {
          Text(vpa)
            .foregroundStyle(NomiColor.textSecondary)
          Spacer()
          Button {
            copyToPasteboard(vpa)
          } label: {
            Image(systemName: "doc.on.doc")
              .foregroundStyle(NomiColor.textTertiary)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(NomiSpacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(NomiColor.surfaceRow)
    .nomiCornerRadius(NomiRadius.inset)
  }

  // MARK: - Actions

  /// This package's `swift test` also builds for plain macOS (see
  /// `AccountsScreen`'s note on `.swipeActions`), so the copy button needs
  /// both pasteboard APIs, not just `UIPasteboard`.
  private func copyToPasteboard(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.string = text
    #elseif os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #endif
  }

  private func prefillEditIfNeeded(_ transaction: NomiCore.Transaction) {
    guard !didPrefillEdit else { return }
    didPrefillEdit = true
    amountText = String(format: "%.2f", Double(transaction.amountMinor) / 100)
    editedDate = transaction.date
    editedDescription = transaction.descriptionText
    editedNote = transaction.note ?? ""
  }

  /// The suggestion read is a `do`/`catch` to `nil` — an assist that fails is
  /// an assist that is absent, and this is the one place in this screen a
  /// swallowed error is correct: the panel just doesn't show, no `.alert`.
  private func refreshSuggestion() {
    guard let suggester else {
      suggestion = nil
      return
    }
    do {
      suggestion = try suggester.suggestion(for: transactionID)
    } catch {
      suggestion = nil
    }
  }

  private func updateCategory(to categoryID: UUID) {
    do {
      try transactionStore.setCategory(transactionID, to: categoryID)
      refreshSuggestion()
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
        transactionID, amountMinor: editedAmountMinor, date: editedDate, descriptionText: editedDescription,
        note: TransactionDetailLogic.noteToSave(from: editedNote))
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

  /// U24: none of `PreviewData.transactions` carries a note, so the
  /// done-when's "row with a note" preview needs its own fixture, same
  /// convention as `manual` above.
  static let noted: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -1 * 86400)
    let description = "DINE OUT/SWIGGY/REF2"
    let normalized = normalizeDescription(description)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
      date: date,
      descriptionText: description,
      merchantName: "Swiggy",
      normalizedDescription: normalized,
      amountMinor: 68_00,
      directionRaw: Direction.debit.rawValue,
      categoryID: PreviewData.categories[0].id,
      categorySourceRaw: CategorySource.manual.rawValue,
      accountID: PreviewData.accounts[0].id,
      sourceRaw: IngestSource.email.rawValue,
      sourceRefs: [SourceRef(source: .email, externalID: UUID().uuidString, capturedAt: date)],
      dedupeKey: makeDedupeKey(
        date: date, amountMinor: 68_00, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
      ),
      createdAt: date,
      updatedAt: date,
      note: "Split with Riya"
    )
  }()
}

extension TransactionDetailPreviewFixtures {
  /// U18: a foreign-currency row, for the "detail with a USD edit field"
  /// done-when — `PreviewData.transactions` has no non-INR fixture.
  static let usd: NomiCore.Transaction = {
    let date = Date(timeIntervalSinceNow: -2 * 86400)
    let description = "AMAZON.COM AMZN.COM/BILL WA"
    let normalized = normalizeDescription(description)
    return NomiCore.Transaction(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000603")!,
      date: date,
      descriptionText: description,
      merchantName: "Amazon",
      normalizedDescription: normalized,
      amountMinor: 1299,
      currencyCode: "USD",
      directionRaw: Direction.debit.rawValue,
      accountID: PreviewData.accounts[0].id,
      sourceRaw: IngestSource.email.rawValue,
      sourceRefs: [SourceRef(source: .email, externalID: UUID().uuidString, capturedAt: date)],
      dedupeKey: makeDedupeKey(
        date: date, amountMinor: 1299, directionRaw: Direction.debit.rawValue, normalizedDescription: normalized
      ),
      createdAt: date,
      updatedAt: date
    )
  }()
}

#Preview("Transaction detail — USD edit field, dark") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.usd]
  TransactionDetailScreen(
    transactionID: TransactionDetailPreviewFixtures.usd.id,
    transactionStore: FakeTransactionStore(transactions: transactions),
    editor: FakeTransactionEditor(transactions: transactions),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — flagged email row, dark") {
  let transaction = PreviewData.transactions.first { $0.needsReview }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — merged row, dark") {
  let transaction = PreviewData.transactions.first { $0.mergedCount > 1 }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

/// The `.manual` row carries a real suggestion from the fake suggester —
/// proving the panel stays hidden because of `categorySource`, not merely
/// because nothing was suggested.
#Preview("Transaction detail — manual row, suggestion still hidden, dark") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.manual]
  let suggested = PreviewData.categories.first { $0.id != TransactionDetailPreviewFixtures.manual.categoryID }!
  TransactionDetailScreen(
    transactionID: TransactionDetailPreviewFixtures.manual.id,
    transactionStore: FakeTransactionStore(transactions: transactions),
    editor: FakeTransactionEditor(transactions: transactions),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore(),
    suggester: FakeCategorySuggester(suggestion: CategorySuggestion(categoryID: suggested.id, reason: .merchantHistory(matches: 4)))
  )
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

/// U24 done-when: "row with a note" — `.noted` — paired with every row above
/// this one, which all come from `PreviewData.transactions` and so already
/// cover "row without".
#Preview("Transaction detail — with a note, dark") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.noted]
  TransactionDetailScreen(
    transactionID: TransactionDetailPreviewFixtures.noted.id,
    transactionStore: FakeTransactionStore(transactions: transactions),
    editor: FakeTransactionEditor(transactions: transactions),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.dark)
}

/// M4: `FakeCategorySuggester` returning a real suggestion for a non-manual
/// row — the panel shows, with both pills.
#Preview("Transaction detail — suggestion shown, dark") {
  let transaction = PreviewData.transactions.first { $0.categorySource != .manual }!
  let suggested = PreviewData.categories.first { $0.id != transaction.categoryID }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore(),
    suggester: FakeCategorySuggester(suggestion: CategorySuggestion(categoryID: suggested.id, reason: .rule(ruleID: UUID())))
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

/// M4: no suggester at all (the default every other preview above already
/// uses) — named explicitly for the "without one" done-when, same rule
/// `Dashboard — no recurring store` follows in `DashboardView.swift`.
#Preview("Transaction detail — no suggestion, dark") {
  let transaction = PreviewData.transactions.first { $0.categorySource != .manual }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.dark)
}

#Preview("Transaction detail — accessibility 3, dark") {
  let transaction = PreviewData.transactions.first { $0.mergedCount == 1 && !$0.needsReview }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .environment(\.dynamicTypeSize, .accessibility3)
  .preferredColorScheme(.dark)
}
