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
  @discardableResult func create(pattern: String, categoryID: UUID) throws -> RuleApplyResult
  @discardableResult func update(_ id: UUID, pattern: String, categoryID: UUID) throws -> RuleApplyResult
  func delete(_ id: UUID) throws
  func reorder(_ orderedIDs: [UUID]) throws
  func preview(pattern: String) throws -> Int
}

@MainActor
public protocol InsightsStore: AnyObject {
  func insights(for period: InsightPeriod) throws -> PeriodInsights
  func trend(months: Int) throws -> [MonthBucket]
  func accountSummaries(includeArchived: Bool) throws -> [AccountSummary]
  func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress]
  func transactions(in period: InsightPeriod) throws -> [Transaction]
}

@MainActor
public protocol BudgetStore: AnyObject {
  func setBudget(categoryID: UUID, amountMinor: Int) throws
  func removeBudget(categoryID: UUID) throws
  func budgets() throws -> [Budget]
}

@MainActor
public protocol AccountStore: AnyObject {
  /// Creates and persists an `Account`.
  ///
  /// Both string constraints are the caller's to hold, not this contract's:
  /// `displayName` is required and non-blank, and `lastFour` is exactly four
  /// digits or empty — never partial. The UI gates on both before it gets
  /// here (`AccountCreateFormGate`), and a store that re-validated would have
  /// to invent an error case for a state the only caller cannot produce.
  ///
  /// `kindRaw` is a `String` because `Account.kindRaw` is one; there is no
  /// `AccountKind` enum and this is not the unit that introduces it. The fixed
  /// choices live in `NomiUI`, the way `PaletteSlotOptions` does for categories.
  @discardableResult
  func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String
  ) throws -> Account

  func rename(_ id: UUID, to displayName: String) throws
  func setArchived(_ id: UUID, _ archived: Bool) throws
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
  func startBackfill(months: Int) async throws
}

public protocol FileImportService: AnyObject, Sendable {
  func inspect(_ url: URL) async throws -> ImportPreview
  func commit(_ url: URL, mapping: ColumnMapping, accountID: UUID?) async throws -> ImportSummary
  func saveMapping(_ mapping: ColumnMapping, signature: String, bankLabel: String) throws
}
