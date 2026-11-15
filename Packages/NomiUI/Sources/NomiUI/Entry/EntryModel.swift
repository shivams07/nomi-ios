import Foundation
import NomiCore
import Observation

/// The writes and hint reads the entry sheet uses. The model depends on this
/// narrow protocol rather than on all of `TransactionStore`, so a test can spy on
/// the calls. `TransactionStore` already has every requirement, so it conforms
/// with no code of its own.
@MainActor
protocol EntryTransactionWriting: AnyObject {
  func add(_ draft: ManualTransactionDraft) throws -> Transaction
  func addTransfer(
    amountMinor: Int, date: Date, fromAccountID: UUID, toAccountID: UUID, note: String?
  ) throws -> (Transaction, Transaction)
  func lastUsedAccountID() -> UUID?
  func lastUsedCategoryID() -> UUID?
  func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID]
}

/// Forwards each call to the app's `TransactionStore`. The view wraps the store in
/// this once, so the model never names the whole store.
@MainActor
final class EntryStoreWriter: EntryTransactionWriting {
  private let store: TransactionStore

  init(_ store: TransactionStore) {
    self.store = store
  }

  func add(_ draft: ManualTransactionDraft) throws -> Transaction {
    try store.add(draft)
  }

  func addTransfer(
    amountMinor: Int, date: Date, fromAccountID: UUID, toAccountID: UUID, note: String?
  ) throws -> (Transaction, Transaction) {
    try store.addTransfer(
      amountMinor: amountMinor,
      date: date,
      fromAccountID: fromAccountID,
      toAccountID: toAccountID,
      note: note
    )
  }

  func lastUsedAccountID() -> UUID? {
    store.lastUsedAccountID()
  }

  func lastUsedCategoryID() -> UUID? {
    store.lastUsedCategoryID()
  }

  func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID] {
    try store.suggestedCategories(forDescription: text, limit: limit)
  }
}

/// One account the entry sheet can offer: a value snapshot of `NomiCore.Account`.
struct EntryAccountOption: AccountArchivable, Equatable {
  let id: UUID
  let displayName: String
  let isArchived: Bool
}

extension EntryAccountOption {
  init(_ account: NomiCore.Account) {
    self.init(id: account.id, displayName: account.displayName, isArchived: account.isArchived)
  }
}

/// One category the entry sheet can offer: a value snapshot of `NomiCore.Category`.
struct EntryCategoryOption: Equatable {
  let id: UUID
  let name: String
  let symbolName: String
  let paletteSlot: Int
}

extension EntryCategoryOption {
  init(_ category: NomiCore.Category) {
    self.init(
      id: category.id,
      name: category.name,
      symbolName: category.symbolName,
      paletteSlot: category.paletteSlot
    )
  }
}

/// The state and rules of the manual-entry sheet (S5). The view draws it and
/// forwards taps; every rule the sheet enforces lives here so a test can pin it.
///
/// Spent and Income write one row. Transfer writes a linked pair through
/// `addTransfer`, never `add`. The amount is the only required input for Spent
/// and Income. A transfer also needs two different accounts. Payee, category,
/// date and note are optional.
@MainActor
@Observable
final class EntryModel {
  enum Kind: Hashable, CaseIterable, Sendable {
    case spent
    case income
    case transfer
  }

  /// How many category suggestions the sheet offers at most.
  static let suggestionLimit = 3

  private let store: EntryTransactionWriting
  private let suggestionDelay: Duration
  @ObservationIgnored private var suggestionTask: Task<Void, Never>?

  private(set) var accounts: [EntryAccountOption]
  private(set) var categories: [EntryCategoryOption]

  var kind: Kind = .spent {
    didSet {
      if !availableKinds.contains(kind) { kind = .spent }
    }
  }

  /// The amount as typed. Kept to digits and the first separator, so the field
  /// cannot hold a second separator or a letter.
  var amountText: String = "" {
    didSet {
      let sanitized = EntryAmount.sanitizeInput(amountText)
      if sanitized != amountText { amountText = sanitized }
    }
  }

  /// "Paid to" or "Received from" (the description). A change asks for suggestions
  /// after a pause.
  var payee: String = "" {
    didSet { payeeDidChange() }
  }

  var categoryID: UUID?
  /// The account of a spent or income entry, or the "From" account of a transfer.
  var accountID: UUID?
  /// The "To" account of a transfer.
  var toAccountID: UUID?
  var date: Date
  var note: String = ""
  var errorMessage: String?

  /// Category ids the store suggests for the payee. At most `suggestionLimit`.
  private(set) var suggestions: [UUID] = []

  init(
    store: EntryTransactionWriting,
    accounts: [EntryAccountOption],
    categories: [EntryCategoryOption],
    now: Date = Date(),
    suggestionDelay: Duration = .milliseconds(250)
  ) {
    self.store = store
    self.accounts = accounts
    self.categories = categories
    self.date = now
    self.suggestionDelay = suggestionDelay

    // Prefill from what the user last did, but only from what can still be shown:
    // a deleted category or an archived account is not prefilled.
    let lastCategory = store.lastUsedCategoryID()
    categoryID = categories.first(where: { $0.id == lastCategory })?.id
    accountID = EntryAccountDefault.initial(lastUsed: store.lastUsedAccountID(), from: accounts)
  }

  // MARK: - Lists

  /// Replaces the account and category lists the sheet reads. The view calls
  /// this when they change while the sheet is open (a category created from the
  /// picker, for example). A selection that no longer exists is cleared.
  func updateLists(accounts: [EntryAccountOption], categories: [EntryCategoryOption]) {
    self.accounts = accounts
    self.categories = categories
    if !availableKinds.contains(kind) { kind = .spent }
    if let categoryID, !categories.contains(where: { $0.id == categoryID }) {
      self.categoryID = nil
    }
    if let accountID, !accounts.contains(where: { $0.id == accountID }) {
      self.accountID = nil
    }
    if let toAccountID, !accounts.contains(where: { $0.id == toAccountID }) {
      self.toAccountID = nil
    }
  }

  var activeAccounts: [EntryAccountOption] {
    accounts.filter { !$0.isArchived }
  }

  /// Transfer needs an account to move money between, so it is offered only when
  /// there is one. Spent and Income are always offered.
  var availableKinds: [Kind] {
    activeAccounts.isEmpty ? [.spent, .income] : Kind.allCases
  }

  func accountName(_ id: UUID?) -> String? {
    guard let id else { return nil }
    return accounts.first(where: { $0.id == id })?.displayName
  }

  func categoryOption(_ id: UUID?) -> EntryCategoryOption? {
    guard let id else { return nil }
    return categories.first(where: { $0.id == id })
  }

  // MARK: - Amount

  var amountMinor: Int {
    EntryAmount.minorUnits(from: amountText)
  }

  var amountDisplay: EntryAmountDisplay {
    EntryAmountDisplay.of(amountText)
  }

  var isTransfer: Bool { kind == .transfer }

  // MARK: - Save gate and copy

  /// Two different accounts, both chosen. A transfer with a missing account, or
  /// with the same account on both sides, is not valid.
  private var transferAccountsAreDistinct: Bool {
    guard let accountID, let toAccountID else { return false }
    return accountID != toAccountID
  }

  /// Save is enabled when the amount is positive and valid. A transfer also needs
  /// two different accounts. Nothing else gates Save.
  var canSave: Bool {
    guard EntrySaveGate.isEnabled(amountMinor: amountMinor) else { return false }
    return isTransfer ? transferAccountsAreDistinct : true
  }

  /// The line under the Save button for a transfer that cannot be saved yet.
  var transferCaption: String? {
    guard isTransfer, !transferAccountsAreDistinct else { return nil }
    return "Choose two different accounts"
  }

  /// "Save ₹<amount> to <category>", "Save ₹<amount>", or "Save transfer of ₹<amount>".
  var saveTitle: String {
    let amount = NomiFormatters.amountString(minor: amountMinor)
    if isTransfer {
      return "Save transfer of \(amount)"
    }
    if let name = categoryOption(categoryID)?.name {
      return "Save \(amount) to \(name)"
    }
    return "Save \(amount)"
  }

  /// The payee as saved: surrounding whitespace removed.
  private var trimmedPayee: String {
    payee.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// The heading over the suggestion chips, naming the payee. Nil when there is no
  /// payee, so the heading never reads "to " with nothing after it.
  var suggestionHeading: String? {
    guard !trimmedPayee.isEmpty, !visibleSuggestions.isEmpty else { return nil }
    return "Suggested from past payments to \(trimmedPayee)"
  }

  /// The suggestions the sheet shows: none for a transfer, and only categories the
  /// picker can show.
  var visibleSuggestions: [EntryCategoryOption] {
    guard !isTransfer else { return [] }
    return suggestions.compactMap { id in categories.first(where: { $0.id == id }) }
  }

  // MARK: - Suggestions

  private func payeeDidChange() {
    suggestionTask?.cancel()
    let delay = suggestionDelay
    suggestionTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.refreshSuggestions()
    }
  }

  /// Asks the store for suggestions for the payee now. The view reaches this
  /// through the debounced path. A test calls it directly.
  func refreshSuggestions() {
    guard !isTransfer else {
      suggestions = []
      return
    }
    let ids = (try? store.suggestedCategories(forDescription: payee, limit: Self.suggestionLimit)) ?? []
    suggestions = Array(ids.prefix(Self.suggestionLimit))
  }

  // MARK: - Save

  /// Writes the entry. Returns true when a row (or a linked pair) was written.
  /// On a store error it sets `errorMessage` and returns false, so the sheet
  /// stays open with every field as the user left it.
  @discardableResult
  func save() -> Bool {
    guard canSave else { return false }
    do {
      switch kind {
      case .transfer:
        guard let fromID = accountID, let toID = toAccountID else { return false }
        _ = try store.addTransfer(
          amountMinor: amountMinor,
          date: date,
          fromAccountID: fromID,
          toAccountID: toID,
          note: note
        )
      case .spent, .income:
        let draft = ManualTransactionDraft(
          date: date,
          amountMinor: amountMinor,
          descriptionText: trimmedPayee,
          direction: kind == .spent ? .debit : .credit,
          categoryID: categoryID,
          accountID: accountID,
          note: note
        )
        _ = try store.add(draft)
      }
      return true
    } catch {
      errorMessage = "Could not save the transaction."
      return false
    }
  }
}
