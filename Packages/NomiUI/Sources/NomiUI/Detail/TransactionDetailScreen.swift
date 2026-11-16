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

/// The transaction detail sheet, on one `.large` detent (S3a, the Detail
/// artboard). The read state shows the header (badge, merchant, amount, day and
/// account), the category card with its "Always use this" rule switch, the
/// transfer and note card, the bank alert quote, the account and date rows,
/// source details and UPI, and Delete at the foot. Edit swaps the bar to Cancel /
/// Save and shows the amount, description and note fields, with Delete at the
/// bottom (the edit form moves to its own sheet in S3b).
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
/// user thinks their edit or delete took effect when it didn't. The deliberate
/// exceptions are the suggestion read and the rule's match count, which are
/// assists: when they cannot be read they are left out.
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Read only: the transfer partner is found by the shared group id (DEC-05 T3).
  /// The screen writes through `editor`, never through this context. The rule
  /// switch also reads its rules from here, fresh at each toggle (see
  /// `storedRules`), because the `@Query` above does not refresh for a rule the
  /// rule store just wrote.
  @Environment(\.modelContext) private var modelContext
  /// "Always use this for <merchant>" writes go through the rule store (S3a).
  /// Nil hides the rule row.
  @Environment(\.nomiRuleStore) private var ruleStore

  /// Whether the rule switch is on, read from the store after each write.
  @State private var ruleIsOn = false
  /// Bumped when a rule write fails, so the switch redraws in its prior state.
  @State private var ruleSwitchRevision = 0
  @State private var isEditing = false
  /// The note as the read state's row shows it. Written on submit.
  @State private var readNote = ""
  /// How many past rows the pattern matches (`RuleStore.preview`). Nil when it
  /// cannot be read, and the caption is then left out.
  @State private var matchCount: Int?
  /// Set for two seconds after the switch turns a rule on, to show what it
  /// recategorised in place of the match caption.
  @State private var appliedCount: Int?

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

  /// The account's name, or nil for a row with no account (the caption leaves it out).
  private func accountNameIfAssigned(_ transaction: NomiCore.Transaction) -> String? {
    transaction.accountID.flatMap { id in accounts.first { $0.id == id }?.displayName }
  }

  private func accountName(for transaction: NomiCore.Transaction) -> String {
    accountNameIfAssigned(transaction) ?? String(localized: "No account assigned", bundle: .module)
  }

  /// The merchant name, or the bank text when there is none, as the header and
  /// the delete alert name the row.
  private func titleText(_ transaction: NomiCore.Transaction) -> String {
    TransactionRow.title(
      merchantName: transaction.merchantName, descriptionText: transaction.descriptionText,
      categoryName: categoryName(for: transaction))
  }

  /// A transfer leg has no category to suggest, so the panel never shows on one.
  private func isSuggestionShown(for transaction: NomiCore.Transaction) -> Bool {
    guard TransactionDetailLogic.suggestionAllowed(isTransfer: transaction.isTransfer) else { return false }
    return SuggestionRow.isShown(
      suggestion: suggestion, currentCategoryID: transaction.categoryID, categorySource: transaction.categorySource)
  }

  /// The merchant pattern this row would be ruled by, or nil when there is none.
  private func rulePattern(for transaction: NomiCore.Transaction) -> String? {
    MerchantRulePattern.pattern(
      merchantName: transaction.merchantName, normalizedDescription: transaction.normalizedDescription)
  }

  /// The alert body: what the delete takes out of every total (States board).
  private var deleteMessage: String {
    guard let transaction else { return "" }
    return TransactionDetailLogic.deleteConfirmationSentence(
      amountText: NomiFormatters.amountString(minor: transaction.amountMinor, currencyCode: transaction.currencyCode),
      merchant: titleText(transaction), date: transaction.date, calendar: .current)
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
            readNote = transaction.note ?? ""
            refreshRuleState(for: transaction)
            refreshMatchCount(for: transaction)
          }
          .onChange(of: transaction.note) { _, newValue in
            readNote = newValue ?? ""
          }
          .onChange(of: transaction.categoryID) { _, _ in
            refreshRuleState(for: transaction)
          }
          .task(id: appliedCount) {
            guard appliedCount != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            appliedCount = nil
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
    .nomiSheet(detents: [.large])
    .alert("Delete this transaction?", isPresented: $isConfirmingDelete) {
      Button("Delete", role: .destructive) { performDelete() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(deleteMessage)
    }
    .sheet(isPresented: $isCategoryPickerPresented) {
      CategoryPickerSheet(categoryStore: categoryStore, selection: categorySelection, allowsNone: true)
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

  /// Read state: Close on the leading side, Edit on the trailing side. Edit
  /// state: Cancel and Save.
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
          Text("Close")
            .nomiTextStyle(.navAction)
            .foregroundStyle(NomiColor.navy)
        }
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

  /// The read state in artboard order. The suggestion card, when one shows, sits
  /// above the category card; the primary "Mark reviewed" sits under the category
  /// card (D7).
  @ViewBuilder
  private func readContent(_ transaction: NomiCore.Transaction) -> some View {
    let showsSuggestion = isSuggestionShown(for: transaction)
    let primary = TransactionDetailLogic.primaryAction(
      hasSuggestion: showsSuggestion, needsReview: transaction.needsReview)
    let reviewed = TransactionDetailLogic.markReviewedPlacement(primary: primary, needsReview: transaction.needsReview)
    header(transaction)
    if showsSuggestion, let suggestion {
      suggestionCard(transaction: transaction, suggestion: suggestion, primary: primary)
    }
    categoryCard(transaction)
    if transaction.needsReview {
      Text(TransactionDetailLogic.reviewReasonText(transaction.needsReviewReason))
        .nomiTextStyle(.caption)
        .foregroundStyle(NomiColor.inkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NomiSpacing.sm)
    }
    if reviewed == .primaryUnderCategory {
      markReviewedButton(isPrimary: true)
    }
    transferAndNoteCard(transaction)
    bankAlertInset(transaction)
    accountAndDateRows(transaction)
    if reviewed == .secondaryInLargeDetails {
      markReviewedButton(isPrimary: false)
    }
    sourceDetails(transaction)
    if transaction.upiKindRaw != nil {
      upiCard(transaction)
    }
    deleteButton
  }

  private func header(_ transaction: NomiCore.Transaction) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      let category = categoryFor(transaction)
      NomiCategoryBadge(symbolName: category?.symbolName ?? "questionmark", paletteSlot: category?.paletteSlot, size: 56)
        .accessibilityHidden(true)
      Text(titleText(transaction))
        .nomiTextStyle(.headline)
        .foregroundStyle(NomiColor.ink)
        .multilineTextAlignment(.center)
      amountLine(transaction)
      Text(
        TransactionDetailLogic.caption(
          date: transaction.date, now: Date(), calendar: .current,
          accountName: accountNameIfAssigned(transaction))
      )
      .nomiTextStyle(.caption)
      .foregroundStyle(NomiColor.inkSecondary)
      .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }

  /// The sheet amount, signed and coloured by direction (DEC-03, R1): debit "−"
  /// in `ink`, credit "+" in `navy`, both SemiBold at the 46 pt hero size, the
  /// decimals dimmed. Typeset here rather than with `NomiAmountText`, which has
  /// no colour parameter.
  private func amountLine(_ transaction: NomiCore.Transaction) -> some View {
    let isCredit = transaction.direction == .credit
    let signed = TransactionDetailLogic.signedMinor(amountMinor: transaction.amountMinor, direction: transaction.direction)
    let parts = NomiAmountFormat.parts(minor: signed, currencyCode: transaction.currencyCode, showPlus: isCredit)
    let color = isCredit ? NomiColor.navy : NomiColor.ink
    let font = NomiTextStyle.heroAmount.font
    let decimalColor = color.opacity(NomiColor.decimalOpacityGround)
    let spoken = (isCredit ? "Credit, " : "Debit, ") + parts.sign + parts.integer + parts.decimals
    return (Text(parts.sign + parts.integer)
      .font(font)
      .foregroundStyle(color)
      + Text(parts.decimals)
      .font(font)
      .foregroundStyle(decimalColor))
      .tracking(-1.4)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(spoken)
  }

  // MARK: - Category card and rule switch

  /// The category card: the Category row with its chip, then the "Always use
  /// this" switch when the row can take a rule (`TransactionDetailLogic.showsRuleRow`).
  private func categoryCard(_ transaction: NomiCore.Transaction) -> some View {
    let pattern = rulePattern(for: transaction)
    let showsRule = TransactionDetailLogic.showsRuleRow(
      hasRuleStore: ruleStore != nil, isTransfer: transaction.isTransfer, pattern: pattern)
    // At accessibility sizes the label sits above the chip, so neither is squeezed
    // into the other's width; the chip then has the card's full width to wrap in.
    let stacked = dynamicTypeSize.isAccessibilitySize
    return VStack(spacing: 0) {
      Group {
        if stacked {
          VStack(alignment: .leading, spacing: NomiSpacing.xs) {
            Text("Category")
              .nomiTextStyle(.rowTitle)
              .foregroundStyle(NomiColor.ink)
              .fixedSize(horizontal: false, vertical: true)
            categoryChip(transaction)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          HStack(spacing: NomiSpacing.xs) {
            Text("Category")
              .nomiTextStyle(.rowTitle)
              .foregroundStyle(NomiColor.ink)
              .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: NomiSpacing.xs)
            categoryChip(transaction)
          }
        }
      }
      .frame(minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
      if showsRule, let pattern {
        hairline
        NomiToggleRow(
          title: "Always use this for \(MerchantRulePattern.displayName(merchantName: transaction.merchantName, normalizedDescription: transaction.normalizedDescription))",
          caption: ruleCaption(transaction, pattern: pattern),
          isOn: ruleBinding(transaction, pattern: pattern)
        )
        .id(ruleSwitchRevision)
        .disabled(!TransactionDetailLogic.ruleSwitchEnabled(categoryID: transaction.categoryID))
        .padding(.vertical, NomiSpacing.xs)
      }
    }
    .padding(.horizontal, NomiSpacing.sm)
    .padding(.vertical, NomiSpacing.xxs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .nomiCard(padding: EdgeInsets())
  }

  /// The selected category as a primary-filled chip. It opens the picker, which
  /// offers None (S13). A transfer leg has no category, so its chip reads
  /// "Transfer" and does not open.
  private func categoryChip(_ transaction: NomiCore.Transaction) -> some View {
    Button {
      isCategoryPickerPresented = true
    } label: {
      HStack(spacing: NomiSpacing.xxs) {
        // One line, scaled down rather than wrapped: a category name never breaks
        // mid-word or across a hyphen at any text size.
        Text(
          TransactionDetailLogic.categoryChipText(
            isTransfer: transaction.isTransfer, categoryName: categoryName(for: transaction))
        )
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .layoutPriority(1)
        Image(systemName: "chevron.down")
          .fixedSize()
          .accessibilityHidden(true)
      }
      .nomiTextStyle(.chipSelected)
      .foregroundStyle(NomiColor.onPrimary)
      .padding(.horizontal, NomiSpacing.sm)
      .frame(minHeight: 36)
      .background(Capsule().fill(NomiColor.primary))
    }
    .buttonStyle(.plain)
    .disabled(!TransactionDetailLogic.categoryChipEnabled(isTransfer: transaction.isTransfer))
    .opacity(TransactionDetailLogic.categoryChipEnabled(isTransfer: transaction.isTransfer) ? 1 : 0.4)
  }

  private var hairline: some View {
    Rectangle()
      .fill(NomiColor.separator)
      .frame(height: 1)
  }

  /// The count under the switch: the matches, said as "match" (S10's ruling),
  /// or the two-second note after a switch-on.
  private func ruleCaption(_ transaction: NomiCore.Transaction, pattern: String) -> String? {
    if let appliedCount {
      return TransactionDetailLogic.appliedText(count: appliedCount)
    }
    guard let matchCount else { return nil }
    return TransactionDetailLogic.matchCountText(count: matchCount, isOn: ruleIsOn)
  }

  /// The rules as the store holds them now. Read fresh, not from the `@Query`,
  /// so a rule the switch just wrote or deleted is seen at once.
  private func storedRules() throws -> [TransactionDetailLogic.RuleRef] {
    try modelContext.fetch(FetchDescriptor<NomiCore.Rule>(sortBy: [SortDescriptor(\.priority)])).map {
      TransactionDetailLogic.RuleRef(id: $0.id, pattern: $0.pattern, categoryID: $0.categoryID, isSystem: $0.isSystem)
    }
  }

  /// The user rule the switch reads for this row's pattern and category, if any.
  private func currentRuleID(for transaction: NomiCore.Transaction, pattern: String) throws -> UUID? {
    guard let categoryID = transaction.categoryID else { return nil }
    return TransactionDetailLogic.existingRuleID(
      among: try storedRules(), pattern: pattern, categoryID: categoryID)
  }

  /// Sets the switch from the store. A read that fails leaves the switch off
  /// and says so, since the switch cannot show a rule it cannot read.
  private func refreshRuleState(for transaction: NomiCore.Transaction) {
    guard let pattern = rulePattern(for: transaction) else {
      ruleIsOn = false
      return
    }
    do {
      ruleIsOn = try currentRuleID(for: transaction, pattern: pattern) != nil
    } catch {
      ruleIsOn = false
      errorMessage = "Could not read this rule."
    }
  }

  private func ruleBinding(_ transaction: NomiCore.Transaction, pattern: String) -> Binding<Bool> {
    Binding(
      get: { ruleIsOn },
      set: { isOn in applyRuleSwitch(transaction, pattern: pattern, turningOn: isOn) }
    )
  }

  /// Carries out one toggle. The decision is made from the store's current rule
  /// (`TransactionDetailLogic.ruleSwitchAction`), then the switch is set from the
  /// store again. A failed write shows an error and leaves the switch in its
  /// prior state.
  private func applyRuleSwitch(_ transaction: NomiCore.Transaction, pattern: String, turningOn: Bool) {
    do {
      let existing = try currentRuleID(for: transaction, pattern: pattern)
      let action = TransactionDetailLogic.ruleSwitchAction(
        turningOn: turningOn, existingRuleID: existing, categoryID: transaction.categoryID)
      switch action {
      case .none:
        break
      case .create(let categoryID):
        // The store re-applies the rule across the ledger; the result says how many
        // past rows it recategorised.
        guard let ruleStore else { break }
        let result = try ruleStore.create(pattern: pattern, categoryID: categoryID)
        appliedCount = result.recategorized
      case .delete(let id):
        // Rows keep their categories: that is the store's existing policy for a
        // deleted rule.
        guard let ruleStore else { break }
        try ruleStore.delete(id)
        appliedCount = nil
      }
      ruleIsOn = try currentRuleID(for: transaction, pattern: pattern) != nil
      refreshMatchCount(for: transaction)
    } catch {
      errorMessage = turningOn ? "Could not save this rule." : "Could not turn this rule off."
      ruleSwitchRevision += 1
    }
  }

  /// The past-row count for this row's pattern. A count that cannot be read is
  /// left out, the same as the suggestion: it is an aid, not an action.
  private func refreshMatchCount(for transaction: NomiCore.Transaction) {
    guard let ruleStore, let pattern = rulePattern(for: transaction) else {
      matchCount = nil
      return
    }
    do {
      matchCount = try ruleStore.preview(pattern: pattern)
    } catch {
      matchCount = nil
    }
  }

  // MARK: - Transfer and note card

  /// The transfer row and the note row, on one card (artboard). Marking uses the
  /// existing `setTransfer` path and its partner copy; the note writes on submit.
  private func transferAndNoteCard(_ transaction: NomiCore.Transaction) -> some View {
    VStack(alignment: .leading, spacing: NomiSpacing.xs) {
      VStack(spacing: 0) {
        Button {
          if transaction.isTransfer {
            unmarkTransfer()
          } else {
            markTransfer()
          }
        } label: {
          HStack(spacing: NomiSpacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
              Text(TransactionDetailLogic.transferButtonTitle(isTransfer: transaction.isTransfer))
                .nomiTextStyle(.rowTitle)
                .foregroundStyle(NomiColor.ink)
              Text(transaction.isTransfer ? TransactionDetailLogic.transferSentence : "Leaves it out of spending totals")
                .nomiTextStyle(.caption)
                .foregroundStyle(NomiColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: NomiSpacing.xxs)
            Image(systemName: "chevron.right")
              .foregroundStyle(NomiColor.inkSecondary)
              .accessibilityHidden(true)
          }
          .padding(.horizontal, NomiSpacing.sm)
          .padding(.vertical, NomiSpacing.xs)
          .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        hairline
        noteRow(transaction)
      }
      .nomiCard(padding: EdgeInsets())
      if let transferNote {
        Text(transferNote)
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, NomiSpacing.sm)
      }
    }
  }

  private func noteRow(_ transaction: NomiCore.Transaction) -> some View {
    HStack(spacing: NomiSpacing.xs) {
      Text("Note")
        .nomiTextStyle(.rowTitle)
        .foregroundStyle(NomiColor.ink)
      TextField("Add a note", text: $readNote)
        .nomiTextStyle(.body)
        .foregroundStyle(NomiColor.ink)
        .multilineTextAlignment(.trailing)
        .submitLabel(.done)
        .accessibilityLabel("Note")
        .onSubmit {
          saveNote(transaction)
        }
    }
    .padding(.horizontal, NomiSpacing.sm)
    .frame(maxWidth: .infinity, minHeight: NomiSpacing.rowMinHeight)
  }

  /// Writes the note when it changed, through the editor with the row's current
  /// amount, date and description.
  private func saveNote(_ transaction: NomiCore.Transaction) {
    let note = TransactionDetailLogic.noteToSave(from: readNote)
    guard note != transaction.note else { return }
    do {
      try editor.update(
        transactionID, amountMinor: transaction.amountMinor, date: transaction.date,
        descriptionText: transaction.descriptionText, note: note)
    } catch {
      readNote = transaction.note ?? ""
      errorMessage = "Could not save the note."
    }
  }

  // MARK: - Bank alert, account and date

  /// The stored bank text, quoted under its source heading. The description is
  /// stored at 160 characters or fewer, so it is shown whole. A manual row has no
  /// bank text, so it shows no inset. A merged row keeps its "Merged from N sources" line here.
  @ViewBuilder
  private func bankAlertInset(_ transaction: NomiCore.Transaction) -> some View {
    if let heading = sourceHeading(transaction.source) {
      VStack(alignment: .leading, spacing: NomiSpacing.xxs) {
        Text(heading)
          .nomiTextStyle(.label)
          .foregroundStyle(NomiColor.ink)
        Text("\u{201C}\(transaction.descriptionText)\u{201D}")
          .nomiTextStyle(.caption)
          .foregroundStyle(NomiColor.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
        if transaction.mergedCount > 1 {
          Text(TransactionDetailLogic.mergedSourcesText(transaction.mergedCount))
            .nomiTextStyle(.caption)
            .foregroundStyle(NomiColor.inkSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, NomiSpacing.sm)
    }
  }

  private func sourceHeading(_ source: IngestSource) -> String? {
    switch source {
    case .email: return String(localized: "From your bank alert", bundle: .module)
    case .file: return String(localized: "From your statement", bundle: .module)
    case .manual: return nil
    }
  }

  /// The account and date rows. They are kept from the earlier detail sheet: an
  /// account can still be assigned and a date corrected from here.
  private func accountAndDateRows(_ transaction: NomiCore.Transaction) -> some View {
    VStack(spacing: NomiSpacing.xs) {
      valueRow(title: "Account", value: accountName(for: transaction)) {
        isAccountPickerPresented = true
      }
      valueRow(title: "Date", value: NomiFormatters.dayMonthYear.string(from: transaction.date)) {
        pickedDate = transaction.date
        isDatePickerPresented = true
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

  // MARK: - Mark reviewed

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

  // MARK: - Source details, UPI and delete

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

  /// The delete action at the foot of the read state: error text, trash glyph, a
  /// pill. It asks first, through the same alert the edit state uses.
  private var deleteButton: some View {
    Button {
      isConfirmingDelete = true
    } label: {
      HStack(spacing: NomiSpacing.xxs) {
        Image(systemName: "trash")
          .accessibilityHidden(true)
        Text("Delete transaction")
      }
      .nomiTextStyle(.button)
      .foregroundStyle(NomiColor.error)
      .frame(maxWidth: .infinity, minHeight: NomiSpacing.minTarget)
      .background(Capsule().fill(NomiColor.card))
      .overlay(Capsule().strokeBorder(NomiColor.errorTint, lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .padding(.top, NomiSpacing.xs)
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
    isEditing = true
  }

  private func endEditing() {
    isEditing = false
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
  /// live from the row, so presenting the picker writes nothing. The picker's
  /// None row reports a nil pick, which clears a categorised row
  /// (see `CategoryPickCommit`).
  private var categorySelection: Binding<UUID?> {
    Binding(
      get: { transaction?.categoryID },
      set: { picked in
        switch CategoryPickCommit.decision(picked: picked, current: transaction?.categoryID) {
        case .keep:
          break
        case .set(let categoryID):
          updateCategory(to: categoryID)
        case .clear:
          clearCategory()
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

  /// The picker's None row: the row loses its category, through the same
  /// `setCategory` write every other pick uses.
  private func clearCategory() {
    do {
      try transactionStore.setCategory(transactionID, to: nil)
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

#Preview("Transaction detail — suggestion shown, light") {
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
