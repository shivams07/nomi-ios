import Foundation

public enum TransactionStoreError: Error, Sendable, Equatable {
  /// The store does not implement the operation. Thrown by the protocol's stub default.
  case unsupported
  /// A transfer needs two different accounts.
  case sameAccount
}

@MainActor
public protocol TransactionStore: AnyObject {
  func add(_ draft: ManualTransactionDraft) throws -> Transaction
  func setCategory(_ id: UUID, to categoryID: UUID?) throws
  func setAccount(_ id: UUID, to accountID: UUID?) throws
  func delete(_ id: UUID) throws
  func reviewQueue() throws -> [Transaction]
  func dismissReview(_ id: UUID) throws
  func lastUsedCategoryID() -> UUID?

  /// Two legs in one save: a debit on `fromAccountID` and a credit on `toAccountID`, same amount and date,
  /// one new transferGroupID, transferSource .manual, categoryID nil, needsReview false, source .manual.
  /// Amount validated by AmountRules (R8) before anything is written. Returns (debit, credit).
  func addTransfer(amountMinor: Int, date: Date, fromAccountID: UUID, toAccountID: UUID, note: String?) throws -> (Transaction, Transaction)
  /// accountID of the most recently created manual row that has one; nil when none.
  func lastUsedAccountID() -> UUID?
  /// Category ids of past non-transfer rows whose normalizedDescription contains normalizeDescription(text),
  /// most frequent first, ties by most recent; at most `limit`; [] when text normalises to fewer than 2 characters.
  func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID]
}

/// Stub defaults for a conformer that does not implement the three transfer and entry-hint requirements.
/// `FakeTransactionStore` and `SwiftDataTransactionStore` override all three.
extension TransactionStore {
  public func addTransfer(amountMinor: Int, date: Date, fromAccountID: UUID, toAccountID: UUID, note: String?) throws -> (Transaction, Transaction) {
    throw TransactionStoreError.unsupported
  }

  public func lastUsedAccountID() -> UUID? { nil }

  public func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID] { [] }
}

@MainActor
public protocol CategoryStore: AnyObject {
  func create(name: String, symbolName: String, paletteSlot: Int) throws -> Category
  func rename(_ id: UUID, to name: String) throws

  /// Changes a category's name, icon and colour in one write.
  ///
  /// The rules are `CategoryEditRules`. A refused edit throws before anything
  /// is written. Nothing here touches a transaction: an edit changes how a
  /// category looks, never which category a row belongs to, so no amount moves.
  /// Like `rename`, it reports no category as moved, so the observer is not
  /// called.
  ///
  /// A strict requirement: every conformer implements it. A conformer that
  /// cannot edit must throw rather than drop the edit, so the editor can show
  /// the refusal.
  func update(_ id: UUID, name: String, symbolName: String, paletteSlot: Int) throws
  func delete(_ id: UUID) throws
}

@MainActor
public protocol RuleStore: AnyObject {
  @discardableResult func create(pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult
  @discardableResult func update(_ id: UUID, pattern: String, categoryID: UUID, scope: RuleScope) throws -> RuleApplyResult

  /// Change only the scope, leaving the pattern and the category alone.
  ///
  /// Separate from `update` for the reason `setEnabled` is: `update` is the
  /// editor saving a whole rule and re-applying across the ledger for the
  /// counts it shows. Narrowing a scope from a row swipe is not that, and
  /// routing it through `update` would make every caller supply a pattern and
  /// a category it has no opinion about.
  ///
  /// It *does* re-apply, unlike `setEnabled`. Widening a scope makes a rule
  /// fire on rows it previously skipped, and those rows exist now — there is
  /// no "next pass" that would pick them up, because ingest only revisits what
  /// it is re-importing.
  func setScope(_ id: UUID, _ scope: RuleScope) throws

  /// Turn a rule off without deleting it, and back on again.
  ///
  /// Deliberately not `update`: `update` re-applies across the ledger and
  /// returns the counts, and disabling is the opposite request — it changes
  /// what happens on the *next* pass and leaves existing categorisations
  /// alone, the same policy `delete` holds to. There is nothing to report, so
  /// there is nothing to return.
  func setEnabled(_ id: UUID, _ enabled: Bool) throws

  /// Throws when `id` names a system rule — one `DefaultRuleSeed` owns.
  ///
  /// The thrown value is the conformer's own. `NomiCore` cannot name a type
  /// declared in `NomiApp`, so what this contract fixes is *that* it throws,
  /// not which case: callers surface the message, and none of them branch on
  /// it.
  ///
  /// Deletion is refused rather than allowed-and-reseeded because a deleted id
  /// is indistinguishable from one that was never seeded — `apply` would
  /// insert it again on the next launch and the rule would reappear with
  /// nothing to explain why. `setEnabled(_:false)` is the affordance that
  /// persists.
  func delete(_ id: UUID) throws
  func reorder(_ orderedIDs: [UUID]) throws

  /// How many rows this pattern *and* scope would match, for the editor's live
  /// count. The scope is applied on top of the pattern, so narrowing a scope
  /// can only ever lower the number.
  func preview(pattern: String, scope: RuleScope) throws -> Int
}

/// The unscoped spellings, kept so that every caller that has no opinion about
/// scope reads as it did before §W2-5.
///
/// These are an extension rather than default arguments on the requirements
/// because Swift does not allow a default value in a protocol requirement. The
/// consequence is worth stating: they are statically dispatched, so a conformer
/// cannot override `create(pattern:categoryID:)` alone and have it called
/// through the protocol. That is the intent — there is one implementation of
/// each behaviour, and it is the scoped one.
///
/// There is no scope-less `update`: one would pass `.any` and reset a scoped rule.
extension RuleStore {
  @discardableResult
  public func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    try create(pattern: pattern, categoryID: categoryID, scope: .any)
  }

  public func preview(pattern: String) throws -> Int {
    try preview(pattern: pattern, scope: .any)
  }
}

@MainActor
public protocol InsightsStore: AnyObject {
  func insights(for period: InsightPeriod) throws -> PeriodInsights
  func trend(months: Int) throws -> [MonthBucket]
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary]
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress]
  func transactions(in period: InsightPeriod) throws -> [Transaction]

  /// One bucket per calendar month of the window `period` implies, ascending,
  /// zero-filled, never including a month that starts after now.
  /// `.month(y, m)`: the six months ending with m. `.financialYear(s)`: April s
  /// to March s+1. `.trailingMonths(n)`: the n months ending with the current
  /// month. `.allTime`: no buckets.
  func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket]

  /// Newest first, at most `limit`. The dashboard's "recent" card (F2).
  ///
  /// It replaces `transactions(in: .allTime)` there, which materialised the
  /// whole ledger on every write to render five rows. A store backed by a
  /// database answers this with a `fetchLimit`; the default below is for
  /// stubs only.
  func recentTransactions(limit: Int) throws -> [Transaction]

  /// D26. Every row with `needsReview == true`, no date bound: the Ledger's
  /// Needs review chip counts this same set (`LedgerFilterPredicate.makeNeedsReview`).
  /// Home's Needs-you count reads it, so the card and the chip agree in any
  /// month. Independent of `insights(for:)`, whose `needsReviewCount` is the
  /// selected period.
  func needsReviewCountAllTime() throws -> Int

  /// I-10. Rows with `accountID == nil`, newest first, transfers included. No
  /// cache: a row bound to an account drops out of this list on the next read,
  /// not after the next cache clear.
  func unassignedTransactions() throws -> [Transaction]
}

extension InsightsStore {
  /// I-10. Stub default, as `recentTransactions` is. Every database store
  /// overrides it; inheriting this one would route the read through
  /// `transactions(in:)` and its cache.
  public func unassignedTransactions() throws -> [Transaction] {
    try transactions(in: .allTime).filter { $0.accountID == nil }.sorted { $0.date > $1.date }
  }

  /// Default for preview and test stubs that hold a handful of rows, so
  /// adding this requirement did not have to reach into files outside the
  /// unit that added it. **Every store that talks to a database overrides
  /// it** - inheriting this one would reintroduce exactly the all-time fetch
  /// F2 removes.
  public func recentTransactions(limit: Int) throws -> [Transaction] {
    Array(
      try transactions(in: .allTime)
        .sorted { $0.date > $1.date }
        .prefix(max(0, limit))
    )
  }

  /// D26. Default for stubs, the same arrangement as `recentTransactions`: a
  /// stub that holds rows in memory counts its own flagged rows, so it answers
  /// the question the Ledger chip answers. It is not 0: a zero here would make
  /// Home's card in every preview and test double disagree with the rows the
  /// double holds. **Every store that talks to a database overrides it**, or
  /// the all-time fetch is paid on each Home render.
  public func needsReviewCountAllTime() throws -> Int {
    try transactions(in: .allTime).filter { $0.needsReview }.count
  }

  /// R12a. Default for stubs, as `recentTransactions` is. A stub that does not
  /// override it has no monthly trend to show, so it reports none. Every store
  /// that holds data overrides it.
  public func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket] { [] }
}

@MainActor
public protocol BudgetStore: AnyObject {
  func setBudget(categoryID: UUID, amountMinor: Int) throws
  func removeBudget(categoryID: UUID) throws
  func budgets() throws -> [Budget]
}

@MainActor
public protocol AccountStore: AnyObject {
  /// Creates and persists an `Account`, or throws `AccountStoreError`.
  ///
  /// **The store is the authority on these three values; the form gate is a
  /// convenience.** This doc used to say the opposite - that the constraints
  /// were the caller's to hold, because a store that re-validated "would have
  /// to invent an error case for a state the only caller cannot produce". That
  /// was true of one SwiftUI form and stopped being true the moment anything
  /// else could call this. `AccountCreateFormGate` still runs, so the user
  /// sees a disabled Save rather than an alert; it is now the fast path in
  /// front of the rule rather than the only place the rule exists.
  ///
  /// - `displayName` trimmed must be non-empty, else `.blankName`.
  /// - `lastFour` must be four ASCII digits or empty, else `.malformedLastFour`.
  ///   Never partial: it is the `cardFragment` half of the `AccountBinding`
  ///   key, so a partial value silently stops mail auto-resolution matching.
  /// - `kindRaw` must be an `AccountKind` raw value, else `.unknownKind`.
  ///
  /// `kindRaw` stays a `String` in this signature on purpose: `Account.kindRaw`
  /// is one, and widening the parameter to `AccountKind` would push the
  /// unknown-string case out to every caller instead of resolving it here.
  @discardableResult
  func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String
  ) throws -> Account

  /// The four-argument `create` with an opening balance (I-11). Validated exactly as `update` validates
  /// one: `AmountRules.isValidOpeningBalance`, else `AmountValidationError.outOfRange`, before anything is written.
  @discardableResult
  func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws -> Account

  func rename(_ id: UUID, to displayName: String) throws
  func setArchived(_ id: UUID, _ archived: Bool) throws

  /// Edits every field of an existing account, under exactly the rules
  /// `create` enforces and throwing the same `AccountStoreError` cases.
  ///
  /// `rename` has no caller in `Packages`, `App` or `scripts`. The account edit
  /// sheet (`AccountRenameSheet`) writes through this.
  ///
  /// `openingBalanceMinor: nil` clears the opening balance rather than leaving
  /// the stored one alone. There is no "unchanged" sentinel here because the
  /// caller is a form that holds every field.
  func update(
    _ id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws

  /// Deletes the account itself and its `AccountBinding`s.
  ///
  /// **Its transactions are kept**, with `accountID` set to `nil`. Deleting
  /// them would delete history the user never asked to lose - an account they
  /// closed is not a year of spending they are disowning - and it would move
  /// every period total the moment they tidied up their account list. The rows
  /// become unowned, which is a state the app already has a shape for: they
  /// surface through `NeedsYouCard` and can be rebound from the detail sheet.
  ///
  /// The bindings go because they are keyed by `(senderDomain, cardFragment)`
  /// onto this account id. Left behind, they would resolve new mail onto an
  /// account that no longer exists.
  ///
  /// Budgets are untouched: they are keyed by category, not by account.
  func delete(_ id: UUID) throws
}

/// Stub default for conformers that predate the opening balance. Two writes, not atomic: a conformer
/// that holds an opening balance overrides this with one save (`SwiftDataAccountStore` does).
extension AccountStore {
  @discardableResult
  public func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws -> Account {
    let account = try create(displayName: displayName, institution: institution, lastFour: lastFour, kindRaw: kindRaw)
    if let openingBalanceMinor {
      try update(
        account.id,
        displayName: displayName,
        institution: institution,
        lastFour: lastFour,
        kindRaw: kindRaw,
        openingBalanceMinor: openingBalanceMinor
      )
    }
    return account
  }
}

/// The pipeline's post-commit hook. U4 calls it, U10 implements it, U8 wires it.
public protocol PostCommitObserver: AnyObject, Sendable {
  func didCommit(affectedCategoryIDs: Set<UUID>) async
}

/// What the app remembers about a mailbox across launches. `MailConnectionState`
/// is in memory and starts at `.disconnected` on every launch, so without this
/// nothing can say "Last synced three days ago" after a relaunch.
///
/// Both values are history, not status: `disconnect` leaves them alone, and a
/// failed sync leaves `lastSync` at the last one that succeeded.
public struct MailConnectionHistory: Sendable, Equatable {
  /// A `connect` has completed successfully on this device at least once.
  public let hasEverConnected: Bool
  /// The last successful `syncNow` or `startBackfill`, by the injected clock.
  public let lastSync: Date?

  public init(hasEverConnected: Bool, lastSync: Date?) {
    self.hasEverConnected = hasEverConnected
    self.lastSync = lastSync
  }

  /// A fresh install: never connected, never synced.
  public static let never = MailConnectionHistory(hasEverConnected: false, lastSync: nil)
}

public protocol MailConnectionService: AnyObject, Sendable {
  var state: AsyncStream<MailConnectionState> { get }
  var backfillProgress: AsyncStream<BackfillProgress> { get }
  /// Synchronous on purpose: the screens read it once, before their state loop
  /// starts, and the value is already on disk.
  var history: MailConnectionHistory { get }
  func connect(_ credentials: IMAPCredentials) async throws
  func disconnect() async throws
  @discardableResult func syncNow() async throws -> SyncSummary
  @discardableResult func startBackfill(months: Int) async throws -> SyncSummary
  /// A mail credential is saved on this device. Synchronous; read once by
  /// ConnectMailScreen's init, like `history`.
  var hasStoredCredential: Bool { get }
  /// Connects with the saved credential. Yields `.connecting`, then `.connected`
  /// or `.failed`, exactly as `connect(_:)` does. Throws `MailError.connectionFailed`
  /// when nothing is saved.
  func reconnectWithStoredCredential() async throws
}

/// The defaults for a conformer that keeps no history and holds no stored
/// credential. Every conformer that predates `history` or the stored-credential
/// reconnect (the fakes, the UI test doubles) inherits them, so none of them had
/// to be edited to add the requirements.
extension MailConnectionService {
  public var history: MailConnectionHistory { .never }
  public var hasStoredCredential: Bool { false }
  public func reconnectWithStoredCredential() async throws { throw MailError.connectionFailed }
}

public protocol FileImportService: AnyObject, Sendable {
  func inspect(_ url: URL) async throws -> ImportPreview
  func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary
  func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws
}
