import Foundation

@MainActor
public protocol TransactionStore: AnyObject {
  func add(_ draft: ManualTransactionDraft) throws -> Transaction
  func setCategory(_ id: UUID, to categoryID: UUID?) throws
  func setAccount(_ id: UUID, to accountID: UUID?) throws
  func delete(_ id: UUID) throws
  func reviewQueue() throws -> [Transaction]
  func dismissReview(_ id: UUID) throws
  func lastUsedCategoryID() -> UUID?
}

@MainActor
public protocol CategoryStore: AnyObject {
  func create(name: String, symbolName: String, paletteSlot: Int) throws -> Category
  func rename(_ id: UUID, to name: String) throws
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
extension RuleStore {
  @discardableResult
  public func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    try create(pattern: pattern, categoryID: categoryID, scope: .any)
  }

  @discardableResult
  public func update(_ id: UUID, pattern: String, categoryID: UUID) throws -> RuleApplyResult {
    try update(id, pattern: pattern, categoryID: categoryID, scope: .any)
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

  /// Newest first, at most `limit`. The dashboard's "recent" card (F2).
  ///
  /// It replaces `transactions(in: .allTime)` there, which materialised the
  /// whole ledger on every write to render five rows. A store backed by a
  /// database answers this with a `fetchLimit`; the default below is for
  /// stubs only.
  func recentTransactions(limit: Int) throws -> [Transaction]
}

extension InsightsStore {
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

  func rename(_ id: UUID, to displayName: String) throws
  func setArchived(_ id: UUID, _ archived: Bool) throws

  /// Edits every field of an existing account, under exactly the rules
  /// `create` enforces and throwing the same `AccountStoreError` cases.
  ///
  /// Not a superset of `rename`, and it does not replace it: `rename` is the
  /// one-field write the detail and picker sheets already do, and widening it
  /// would make every caller pass four values it has no opinion about. This is
  /// the edit sheet's write.
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

/// The pipeline's post-commit hook. U4 calls it, U10 implements it, U8 wires it.
public protocol PostCommitObserver: AnyObject, Sendable {
  func didCommit(affectedCategoryIDs: Set<UUID>) async
}

public protocol MailConnectionService: AnyObject, Sendable {
  var state: AsyncStream<MailConnectionState> { get }
  var backfillProgress: AsyncStream<BackfillProgress> { get }
  func connect(_ credentials: IMAPCredentials) async throws
  func disconnect() async throws
  @discardableResult func syncNow() async throws -> SyncSummary
  @discardableResult func startBackfill(months: Int) async throws -> SyncSummary
}

public protocol FileImportService: AnyObject, Sendable {
  func inspect(_ url: URL) async throws -> ImportPreview
  func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary
  func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws
}
