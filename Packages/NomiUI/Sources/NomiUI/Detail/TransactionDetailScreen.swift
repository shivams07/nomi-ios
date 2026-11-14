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

/// The transaction detail sheet. Medium shows the header and the suggested
/// category; large adds the account, date, "Mark reviewed", the source
/// details and UPI. Edit swaps the bar to Cancel / Save and shows the amount,
/// description and note fields, with Delete at the bottom (DT, the Detail and
/// DetailDeleteConfirm artboards).
///
/// Presented as a `.sheet(item:)` from `LedgerScreen`, which applies its own
/// `.modelContainer`, so the `@Query`s below are safe. The detents belong to
/// this screen: presenters do not set them.
///
/// Closes three dead ends the review queue had no exit from: assigning a
/// category or account to *any* row (not just ones a rule already touched),
/// editing amount/date/description — the only path off a review-queue ₹0 row
/// nothing could parse — and deleting a mis-imported row with a confirmation
/// in front of it. No store call here uses `try?`: every failure surfaces in
/// an `.alert`, because this screen can fail in more places (several
/// independent store calls, not one) and a swallowed failure here means the
/// user thinks their edit or delete took effect when it didn't. The one
/// deliberate exception is the suggestion read below.
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
  /// Read only: the transfer partner is found by the shared group id (DEC-05 T3).
  /// The screen writes through `editor`, never through this context.
  @Environment(\.modelContext) private var modelContext

  /// Medium is the opening detent; Edit forces large (the artboard's edit state
  /// sits at the large top) and Cancel or Save returns to medium.
  @State private var detent: PresentationDetent = .medium
  @State private var isEditing = false

  @State private var isCategoryPickerPresented = false
  @State private var isAccountPickerPresented = false
  @State private var isDatePickerPresented = false
  /// The date the picker is editing. It is written to the row when the picker
  /// closes (see `commitPickedDate`); the edit state has no date field.
  @State private var pickedDate = Date()
  @State private var isConfirmingDelete = false
  @State private var errorMessage: String?
  @State private var suggestion: CategorySuggestion?
  /// What the last mark or unmark made on this screen did (DEC-05 T3). Held
  /// for this sheet only, so it does not survive a reopen; the sentence that
  /// stays is the one that reads `isTransfer`.
  @State private var transferNote: String?

  @State private var amountText = ""
  @State private var editedDescription = ""
  @State private var editedNote = ""

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

  /// Edit is large only, so the sheet cannot be dragged to medium in the middle
  /// of an edit.
  private var sheetDetents: Set<PresentationDetent> {
    isEditing ? [.large] : [.medium, .large]
  }

  private var editedAmountMinor: Int { EntryAmount.minorUnits(from: amountText) }

  /// Save is enabled only when the form changes something and the amount is
  /// valid (DT: "disabled until changed and valid").
  private var canSaveNow: Bool {
    guard let transaction else { return false }
    return canSave(transaction)
  }

  private func canSave(_ transaction: NomiCore.Transaction) -> Bool {
    EntrySaveGate.isEnabled(amountMinor: editedAmountMinor) && hasEditChanges(transaction)
  }

  private func hasEditChanges(_ transaction: NomiCore.Transaction) -> Bool {
    editedAmountMinor != transaction.amountMinor
      || editedDescription != transaction.descriptionText
      || TransactionDetailLogic.noteToSave(from: editedNote) != transaction.note
  }

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

  private func categoryFor(_ transaction: NomiCore.Transaction) -> NomiCore.Category? {
    transaction.categoryID.flatMap { id in categories.first { $0.id == id } }
  }

  private func categoryName(for transaction: NomiCore.Transaction) -> String? {
    categoryFor(transaction)?.name
  }

  private func accountName(for transaction: NomiCore.Transaction) -> String {
    transaction.accountID.flatMap { id in accounts.first { $0.id == id }?.displayName } ?? "Unassigned"
  }

  private func isSuggestionShown(for transaction: NomiCore.Transaction) -> Bool {
    SuggestionRow.isShown(
      suggestion: suggestion, currentCategoryID: transaction.categoryID, categorySource: transaction.categorySource)
  }

  public var body: some View {
    NavigationStack {
      Group {
        if let transaction {
          ScrollView {
            VStack(spacing: NomiSpacing.sm) {
              if isEditing {
                editContent(transaction)
              } else {
                readContent(transaction)
              }
            }
            .padding(.horizontal, NomiSpacing.screenGutter)
            .padding(.top, NomiSpacing.xs)
            .padding(.bottom, NomiSpacing.screenGutter)
          }
          .onAppear {
            refreshSuggestion()
          }
        } else {
          // Reached for a beat after `delete()` dismisses this sheet — the
          // `@Query` above updates before the dismiss animation finishes — and,
          // defensively, for an id that no longer matches any row.
          ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(NomiColor.ground)
      .toolbar { toolbarContent }
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .navigationTitle(isEditing ? "Edit transaction" : "")
    }
    .nomiSheet(detents: sheetDetents, selection: $detent)
    .confirmationDialog(
      "Delete this transaction?", isPresented: $isConfirmingDelete, titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { performDelete() }
      Button("Cancel", role: .cancel) {}
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: categorySelection)
    }
    .sheet(isPresented: $isAccountPickerPresented) {
      AccountPickerSheet(accountStore: accountStore, selection: transaction?.accountID) { newAccountID in
        updateAccount(to: newAccountID)
      }
    }
    .sheet(isPresented: $isDatePickerPresented, onDismiss: commitPickedDate) {
      DatePickerSheet(date: $pickedDate)
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
      presenting: errorMessage,
      actions: { _ in Button("OK", role: .cancel) {} },
      message: { message in Text(message) }
    )
  }

  // MARK: - Toolbar

  /// Read state: close on the leading side, Edit on the trailing side (both
  /// 44 pt). Edit state: Cancel and Save.
  @ToolbarContentBuilder
  private var toolbarContent: some ToolbarContent {
    if isEditing {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          endEditing()
        } label: {
          Text("Cancel")
            .nomiTextStyle(.navAction)
            .foregroundStyle(NomiColor.navy)
        }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button {
          saveEdit()
        } label: {
          Text("Save")
            .nomiTextStyle(.navActionStrong)
            .foregroundStyle(NomiColor.navy)
        }
        .disabled(!canSaveNow)
        .opacity(canSaveNow ? 1 : 0.4)
      }
    } else {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
        } label: {
          NomiNavIcon(systemName: "xmark")
        }
        .accessibilityLabel("Close")
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          startEditing()
        } label: {
          Text("Edit")
            .nomiTextStyle(.navActionStrong)
            .foregroundStyle(NomiColor.navy)
        }
        .disabled(transaction == nil)
      }
    }
  }

  // MARK: - Read state

  @ViewBuilder
  private func readContent(_ transaction: NomiCore.Transaction) -> some View {
    let showsSuggestion = isSuggestionShown(for: transaction)
    let primary = TransactionDetailLogic.primaryAction(
      hasSuggestion: showsSuggestion, needsReview: transaction.needsReview)
    let reviewed = TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: transaction.needsReview)
    header(transaction)
    if showsSuggestion, let suggestion {
      suggestionCard(transaction: transaction, suggestion: suggestion, primary: primary)
    } else {
      categoryRow(transaction)
      // D7: the no-suggestion primary is drawn here at both detents, not in
      // `largeDetails`, so the medium sheet shows it and large draws it once.
      if reviewed == .primaryUnderCategory {
        markReviewedButton(isPrimary: true)
      }
    }
    if detent == .large {
      largeDetails(transaction, primary: primary)
    }
  }

  private func header(_ transaction: NomiCore.Transaction) -> some View {
    VStack(spacing: NomiSpacing.xxs) {
      let category = categoryFor(transaction)
      NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 40)
        .accessibilityHidden(true)
      Text(
        TransactionRow.title(
          merchantName: transaction.merchantName, descriptionText: transaction.descriptionText,
          categoryName: categoryName(for: transaction))
      )
      .nomiTextStyle(.title)
      .foregroundStyle(NomiColor.ink)
      .multilineTextAlignment(.center)
      amountLine(transaction)
      // The note is drawn on large only, as on the artboard. It is still
      // reached by dragging the sheet up.
      if detent == .large, let note = transaction.note {
        Text(note)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .multilineTextAlignment(.center)
      }
      flagChips(transaction)
    }
    .frame(maxWidth: .infinity)
  }

  /// The sheet amount, signed and coloured by direction (DEC-03, A-03): debit
  /// "−" in `ink`, credit "+" in `inkDeep` SemiBold, decimals dimmed. Typeset
  /// here rather than with `NomiAmountText`, which has no colour parameter and
  /// cannot draw credit in `inkDeep`. The 40 pt size is the artboard's; I-3 has
  /// no role at 40, so F1 should add one if this is to become a shared role.
  private func amountLine(_ transaction: NomiCore.Transaction) -> some View {
    let isCredit = transaction.direction == .credit
    let signed = TransactionDetailLogic.signedMinor(amountMinor: transaction.amountMinor, direction: transaction.direction)
    let parts = NomiAmountFormat.parts(minor: signed, currencyCode: transaction.currencyCode, showPlus: isCredit)
    let color = isCredit ? NomiColor.inkDeep : NomiColor.ink
    let font = isCredit
      ? Font.custom(NomiFont.interSemiBold, size: 40, relativeTo: .largeTitle)
      : Font.custom(NomiFont.interRegular, size: 40, relativeTo: .largeTitle)
    let decimalColor = color.opacity(NomiColor.decimalOpacityGround)
    let spoken = (isCredit ? "Credit, " : "Debit, ") + parts.sign + parts.integer + parts.decimals
    return (Text(parts.sign + parts.integer)
      .font(font)
      .foregroundStyle(color)
      + Text(parts.decimals)
      .font(font)
      .foregroundStyle(decimalColor))
      .tracking(-0.8)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(spoken)
  }

  /// Read-only flags: "Merged from N sources", "No account assigned", "Transfer",
  /// and for a flagged row the stored reason (WR-2): "Sender not verified",
  /// "Not in rupees, not counted", "Date couldn't be read", "Amount couldn't be
  /// read", "Read from an unfamiliar email"; otherwise "Needs review".
  /// Inline when they fit, one per line at large text sizes.
  @ViewBuilder
  private func flagChips(_ transaction: NomiCore.Transaction) -> some View {
    let reasons = TransactionDetailLogic.flagReasons(
      accountID: transaction.accountID, needsReview: transaction.needsReview, mergedCount: transaction.mergedCount,
      isTransfer: transaction.isTransfer, needsReviewReason: transaction.needsReviewReason)
    if !reasons.isEmpty {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: NomiSpacing.xxs) {
          ForEach(reasons, id: \.self) { reason in
            flagChip(reason)
          }
        }
        VStack(spacing: NomiSpacing.xxs) {
          ForEach(reasons, id: \.self) { reason in
            flagChip(reason)
          }
        }
      }
    }
  }

  private func flagChip(_ text: String) -> some View {
    Text(text)
      .nomiTextStyle(.label)
      .foregroundStyle(NomiColor.inkDeep)
      .padding(.horizontal, 10)
      .frame(minHeight: 26)
      .background(Capsule().fill(NomiColor.track))
  }

  // MARK: - Suggestion card

  private func suggestionCard(
    transaction: NomiCore.Transaction, suggestion: CategorySuggestion, primary: TransactionDetailLogic.PrimaryAction
  ) -> some View {
    let category = categories.first { $0.id == suggestion.categoryID }
    let categoryName = category?.name ?? "Uncategorized"
    let merchantLabel = transaction.merchantName ?? transaction.descriptionText
    return VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      Label("Suggested category", systemImage: "sparkles")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
      HStack(spacing: NomiSpacing.xs) {
        NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 32)
          .accessibilityHidden(true)
        Text(categoryName)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
      }
      Text(SuggestionRow.reasonText(reason: suggestion.reason, merchantLabel: merchantLabel, categoryName: categoryName))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: NomiSpacing.xs) {
          changeCategoryButton(transaction)
          applyButton(suggestion: suggestion, isPrimary: primary == .apply)
        }
        VStack(spacing: NomiSpacing.xs) {
          changeCategoryButton(transaction)
          applyButton(suggestion: suggestion, isPrimary: primary == .apply)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }

  private func changeCategoryButton(_ transaction: NomiCore.Transaction) -> some View {
    Button("Change category") {
      isCategoryPickerPresented = true
    }
    .buttonStyle(NomiSecondaryButtonStyle())
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
    .background(Capsule().fill(NomiColor.track))
  }

  @ViewBuilder
  private func applyButton(suggestion: CategorySuggestion, isPrimary: Bool) -> some View {
    if isPrimary {
      Button("Apply") {
        updateCategory(to: suggestion.categoryID)
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: NomiSpacing.minTarget))
    } else {
      Button("Apply") {
        updateCategory(to: suggestion.categoryID)
      }
      .buttonStyle(NomiSecondaryButtonStyle())
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
      .background(Capsule().fill(NomiColor.track))
    }
  }

  /// No suggestion is on screen, so the category is a plain row. Without it the
  /// category could not be changed at all (DT: categorise stays reachable).
  private func categoryRow(_ transaction: NomiCore.Transaction) -> some View {
    let name = categoryName(for: transaction) ?? "Uncategorized"
    let category = categoryFor(transaction)
    return Button {
      isCategoryPickerPresented = true
    } label: {
      HStack(spacing: NomiSpacing.xs) {
        NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 32)
          .accessibilityHidden(true)
        Text(name)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
        Spacer(minLength: NomiSpacing.xxs)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Category, \(name)")
    .nomiCard(padding: EdgeInsets())
  }

  // MARK: - Large detail

  private func largeDetails(_ transaction: NomiCore.Transaction, primary: TransactionDetailLogic.PrimaryAction) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      valueRow(title: "Account", value: accountName(for: transaction)) {
        isAccountPickerPresented = true
      }
      valueRow(title: "Date", value: NomiFormatters.dayMonthYear.string(from: transaction.date)) {
        pickedDate = transaction.date
        isDatePickerPresented = true
      }
      transferSection(transaction)
      // Only the suggestion case reaches here: the no-suggestion primary sits
      // under the category row (see `readContent`), so it is not drawn twice.
      if TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: transaction.needsReview)
        == .secondaryInLargeDetails
      {
        markReviewedButton(isPrimary: false)
          .padding(.top, NomiSpacing.xxs)
      }
      sourceDetails(transaction)
      if transaction.upiKindRaw != nil {
        upiCard(transaction)
      }
    }
  }

  /// A label, a value and a chevron on one card row, 52 pt high.
  private func valueRow(title: String, value: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: NomiSpacing.xs) {
        Text(title)
          .nomiTextStyle(.rowBody)
          .foregroundStyle(NomiColor.inkSecondary)
        Spacer(minLength: NomiSpacing.xs)
        Text(value)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
          .multilineTextAlignment(.trailing)
        Image(systemName: "chevron.right")
          .foregroundStyle(NomiColor.inkSecondary)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .nomiCard(padding: EdgeInsets())
  }

  /// The transfer control and the copy that goes with it (DEC-05 T3). It is a
  /// secondary action, so it never takes the screen's single primary. The
  /// sentence stands while the row is a transfer; the note is what the last
  /// mark or unmark on this screen did.
  private func transferSection(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      transferButton(isTransfer: transaction.isTransfer)
      if transaction.isTransfer {
        Text(TransactionDetailLogic.transferSentence)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if let transferNote {
        Text(transferNote)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, NomiSpacing.xxs)
  }

  private func transferButton(isTransfer: Bool) -> some View {
    Button(TransactionDetailLogic.transferButtonTitle(isTransfer: isTransfer)) {
      if isTransfer {
        unmarkTransfer()
      } else {
        markTransfer()
      }
    }
    .buttonStyle(NomiSecondaryButtonStyle())
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
    .background(Capsule().fill(NomiColor.track))
  }

  /// Primary when `primary == .markReviewed`, else the pale secondary pill.
  @ViewBuilder
  private func markReviewedButton(isPrimary: Bool) -> some View {
    if isPrimary {
      Button("Mark reviewed") {
        markReviewed()
      }
      .buttonStyle(NomiPrimaryButtonStyle(height: NomiSpacing.rowMinHeight))
    } else {
      Button("Mark reviewed") {
        markReviewed()
      }
      .buttonStyle(NomiSecondaryButtonStyle())
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
      .background(Capsule().fill(NomiColor.track))
    }
  }

  /// The mono IDs and the raw narration, collapsed by default (SIMP §3 item 11).
  private func sourceDetails(_ transaction: NomiCore.Transaction) -> some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text("Sources")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
        ForEach(TransactionDetailLogic.sourceSummary(refs: transaction.sourceRefs), id: \.self) { line in
          Text(line)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(NomiColor.inkSecondary)
        }
        Text("Merged from \(transaction.mergedCount) source\(transaction.mergedCount == 1 ? "" : "s")")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
        Text(transaction.descriptionText)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(NomiColor.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, NomiSpacing.xxs)
    } label: {
      Text("Source details")
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
    }
    .nomiCard(padding: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
  }

  private func upiCard(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
      Text("UPI")
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
      if let kindRaw = transaction.upiKindRaw {
        Text(UPIDisplay.kindLabel(kindRaw) ?? kindRaw.capitalized)
          .nomiTextStyle(.rowTitle)
          .foregroundStyle(NomiColor.ink)
      }
      if let vpa = transaction.counterpartyVPA {
        HStack(spacing: NomiSpacing.xs) {
          Text(vpa)
            .nomiTextStyle(.rowBody)
            .foregroundStyle(NomiColor.inkDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button {
            copyToPasteboard(vpa)
          } label: {
            Image(systemName: "doc.on.doc")
              .foregroundStyle(NomiColor.inkSecondary)
              .frame(minWidth: NomiSpacing.minTarget, minHeight: NomiSpacing.minTarget)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Copy address")
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
  }

  // MARK: - Edit state

  private func editContent(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      fieldLabel("Amount")
      fieldCard {
        HStack(spacing: NomiSpacing.xxs) {
          Text(currencySymbol)
            .font(Font.custom(NomiFont.interMedium, size: 22, relativeTo: .title2))
            .foregroundStyle(NomiColor.ink)
          TextField("0", text: $amountText)
            .font(Font.custom(NomiFont.interMedium, size: 22, relativeTo: .title2))
            .foregroundStyle(NomiColor.ink)
            .accessibilityLabel("Amount")
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .onChange(of: amountText) { _, newValue in
              let sanitized = EntryAmount.sanitizeInput(newValue)
              if sanitized != newValue { amountText = sanitized }
            }
        }
      }
      fieldLabel("Description")
      fieldCard {
        TextField("Description", text: $editedDescription)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
          .accessibilityLabel("Description")
      }
      fieldLabel("Note")
      fieldCard {
        TextField("Note", text: $editedNote)
          .nomiTextStyle(.body)
          .foregroundStyle(NomiColor.ink)
          .accessibilityLabel("Note")
      }
      NomiDestructiveRow(title: "Delete transaction") {
        isConfirmingDelete = true
      }
      .padding(.horizontal, NomiSpacing.sm)
      .nomiCard(padding: EdgeInsets())
      .padding(.top, NomiSpacing.md)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func fieldLabel(_ text: String) -> some View {
    Text(text)
      .nomiTextStyle(.subhead)
      .foregroundStyle(NomiColor.inkDeep)
      .padding(.leading, NomiSpacing.xxs)
      .padding(.top, NomiSpacing.xxs)
  }

  private func fieldCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.horizontal, NomiSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .nomiCard(padding: EdgeInsets())
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

  private func startEditing() {
    guard let transaction else { return }
    amountText = String(format: "%.2f", Double(transaction.amountMinor) / 100)
    editedDescription = transaction.descriptionText
    editedNote = transaction.note ?? ""
    detent = .large
    isEditing = true
  }

  private func endEditing() {
    isEditing = false
    detent = .medium
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

  /// What the category picker reads and writes. The current category is read
  /// live from the row, so presenting the picker writes nothing, and only a
  /// different pick reaches `updateCategory` (see `CategoryPickCommit`).
  private var categorySelection: Binding<UUID?> {
    Binding(
      get: { transaction?.categoryID },
      set: { picked in
        if CategoryPickCommit.shouldWrite(picked: picked, current: transaction?.categoryID), let picked {
          updateCategory(to: picked)
        }
      }
    )
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
    guard let transaction, canSave(transaction) else { return }
    do {
      try editor.update(
        transactionID, amountMinor: editedAmountMinor, date: transaction.date, descriptionText: editedDescription,
        note: TransactionDetailLogic.noteToSave(from: editedNote))
      endEditing()
    } catch {
      errorMessage = "Could not save the changes."
    }
  }

  /// Runs when the date picker closes, whether by Done or by a swipe. The
  /// picker offers only Done, so a swipe-down also keeps the picked date.
  /// Writes only when the day changed.
  private func commitPickedDate() {
    guard let transaction, pickedDate != transaction.date else { return }
    do {
      try editor.update(
        transactionID, amountMinor: transaction.amountMinor, date: pickedDate,
        descriptionText: transaction.descriptionText, note: transaction.note)
    } catch {
      errorMessage = "Could not update the date."
    }
  }

  private func markReviewed() {
    do {
      try transactionStore.dismissReview(transactionID)
    } catch {
      errorMessage = "Could not mark this reviewed."
    }
  }

  /// DEC-05 T3: marks this row through the editor, then reads back the partner
  /// the same write marked, so the note names it. If the read fails after the
  /// write, the note is dropped and the alert says the mark happened, since
  /// the write did not fail.
  private func markTransfer() {
    do {
      try editor.setTransfer(transactionID, isTransfer: true)
    } catch {
      errorMessage = "Could not mark this as a transfer."
      return
    }
    do {
      let partner = try transferPartner(of: transactionID)
      transferNote = TransactionDetailLogic.markOutcome(partner: partner)
    } catch {
      transferNote = nil
      errorMessage = "Marked as a transfer, but could not read the matching payment."
    }
  }

  /// DEC-05 T3: unmarking clears the partner too, so the partner is read before
  /// the write. If that read fails, nothing is written: the copy must name every
  /// row the write changes, so an unreadable partner stops the unmark.
  private func unmarkTransfer() {
    let partner: TransactionDetailLogic.TransferPartner?
    do {
      partner = try transferPartner(of: transactionID)
      try editor.setTransfer(transactionID, isTransfer: false)
    } catch {
      errorMessage = "Could not unmark this transfer."
      return
    }
    transferNote = TransactionDetailLogic.unmarkOutcome(partner: partner)
  }

  /// The other row in this row's transfer group, read by the shared group id
  /// only (U6: never `transferSource`). `nil` when the row is not a transfer or
  /// has no other leg, which is the "only this transaction" case.
  private func transferPartner(of id: UUID) throws -> TransactionDetailLogic.TransferPartner? {
    var rowDescriptor = FetchDescriptor<NomiCore.Transaction>(predicate: #Predicate { $0.id == id })
    rowDescriptor.fetchLimit = 1
    guard let group = try modelContext.fetch(rowDescriptor).first?.transferGroupID else { return nil }
    let target: UUID? = group
    let partners = try modelContext.fetch(
      FetchDescriptor<NomiCore.Transaction>(predicate: #Predicate { $0.transferGroupID == target && $0.id != id })
    )
    guard let partner = partners.first else { return nil }
    return TransactionDetailLogic.TransferPartner(narration: partner.descriptionText, date: partner.date)
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

#Preview("Transaction detail — medium, suggestion shown, light") {
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
  .preferredColorScheme(.light)
}

#Preview("Transaction detail — USD edit field, light") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.usd]
  TransactionDetailScreen(
    transactionID: TransactionDetailPreviewFixtures.usd.id,
    transactionStore: FakeTransactionStore(transactions: transactions),
    editor: FakeTransactionEditor(transactions: transactions),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.light)
}

#Preview("Transaction detail — flagged email row, light") {
  let transaction = PreviewData.transactions.first { $0.needsReview }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.light)
}

#Preview("Transaction detail — merged row, light") {
  let transaction = PreviewData.transactions.first { $0.mergedCount > 1 }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.light)
}

/// The `.manual` row carries a real suggestion from the fake suggester —
/// proving the panel stays hidden because of `categorySource`, not merely
/// because nothing was suggested.
#Preview("Transaction detail — manual row, suggestion still hidden, light") {
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
  .preferredColorScheme(.light)
}

/// U24 done-when: "row with a note" — `.noted` — paired with every row above
/// this one, which all come from `PreviewData.transactions` and so already
/// cover "row without".
#Preview("Transaction detail — with a note, light") {
  let transactions = PreviewData.transactions + [TransactionDetailPreviewFixtures.noted]
  TransactionDetailScreen(
    transactionID: TransactionDetailPreviewFixtures.noted.id,
    transactionStore: FakeTransactionStore(transactions: transactions),
    editor: FakeTransactionEditor(transactions: transactions),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer(transactions: transactions))
  .preferredColorScheme(.light)
}

/// M4: no suggester at all (the default every other preview above already
/// uses) — named explicitly for the "without one" done-when, same rule
/// `Dashboard — no recurring store` follows in `DashboardView.swift`.
#Preview("Transaction detail — no suggestion, light") {
  let transaction = PreviewData.transactions.first { $0.categorySource != .manual }!
  TransactionDetailScreen(
    transactionID: transaction.id,
    transactionStore: FakeTransactionStore(),
    editor: FakeTransactionEditor(),
    categoryStore: FakeCategoryStore(),
    accountStore: FakeAccountStore()
  )
  .modelContainer(LedgerPreviewSupport.makeContainer())
  .preferredColorScheme(.light)
}

#Preview("Transaction detail — accessibility 3, light") {
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
  .preferredColorScheme(.light)
}
