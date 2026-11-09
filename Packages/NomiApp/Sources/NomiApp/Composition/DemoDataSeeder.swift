#if DEBUG && (targetEnvironment(simulator) || os(macOS))
import Foundation
import NomiCore
import NomiIngest

/// Writes a `DemoDataset` into a store, through the stores.
///
/// **Nothing here writes a row around a store.** Accounts go through
/// `AccountStore`, bank and statement rows through `IngestPipeline.ingest` (the
/// one ingest write path, where dedupe, rules and the DEC-05 transfer detector
/// run), manual entries through `TransactionStore.add`, budgets through
/// `BudgetStore`, and rules through `RuleStore`, which re-applies each rule
/// across the rows already there. The seeder decides nothing itself.
///
/// **Once.** It writes only into a store that holds no transaction and no
/// account. A second launch with the variable still set finds data and returns
/// without writing. To seed again, uninstall the app: that clears the store.
///
/// **Not atomic.** Each store call saves on its own, so a failure part-way
/// leaves a partial store, and the guard then refuses to seed over it. Uninstall
/// to reset. This is a debug-only tool, and a partial demo is easier to notice
/// than a silent retry that doubles the rows.
@MainActor
enum DemoDataSeeder {
  /// The stores the seeder writes through. Passed in, so a test can hand it the
  /// stores of an `AppEnvironment` built over an in-memory container.
  struct Stores {
    let transactions: any TransactionStore
    let accounts: any AccountStore
    let rules: any RuleStore
    let budgets: any BudgetStore
    /// Read only: the empty-store check. Also the cached reads the Home screen uses.
    let insights: any InsightsStore
    let pipeline: IngestPipeline
  }

  enum SeedError: Error, Equatable {
    case unknownCategory(String)
    case unknownAccount(String)
  }

  /// Whether this launch asked for demo data. The only reader of
  /// `NOMI_DEMO_DATA`, and it reads it only in a Debug simulator build. Anywhere
  /// else it is `false` whatever the environment holds.
  static func isRequested(in environment: [String: String]) -> Bool {
    #if DEBUG && targetEnvironment(simulator)
      return environment["NOMI_DEMO_DATA"] == "1"
    #else
      _ = environment
      return false
    #endif
  }

  /// Seeds `dataset` unless the store already holds data. Returns `true` when it
  /// wrote, `false` when the store was not empty and nothing was written.
  @discardableResult
  static func seedIfEmpty(_ dataset: DemoDataset, into stores: Stores) async throws -> Bool {
    guard try stores.insights.recentTransactions(limit: 1).isEmpty else { return false }
    guard try stores.insights.accountSummaries(includeArchived: true).isEmpty else { return false }

    let categoryIDs = Dictionary(uniqueKeysWithValues: DefaultCategorySeed.specs.map { ($0.name, $0.id) })
    func categoryID(_ name: String) throws -> UUID {
      guard let id = categoryIDs[name] else { throw SeedError.unknownCategory(name) }
      return id
    }

    // Accounts first: every row and rule names one. Opening balances are set by
    // a second `update`, because `create` has no parameter for them.
    var accountIDs: [String: UUID] = [:]
    for account in dataset.accounts {
      let created = try stores.accounts.create(
        displayName: account.displayName,
        institution: account.institution,
        lastFour: account.lastFour,
        kindRaw: account.kind.rawValue)
      if let opening = account.openingBalanceMinor {
        try stores.accounts.update(
          created.id,
          displayName: account.displayName,
          institution: account.institution,
          lastFour: account.lastFour,
          kindRaw: account.kind.rawValue,
          openingBalanceMinor: opening)
      }
      accountIDs[account.key] = created.id
    }

    func accountID(_ key: String?) throws -> UUID? {
      guard let key else { return nil }
      guard let id = accountIDs[key] else { throw SeedError.unknownAccount(key) }
      return id
    }

    for budget in dataset.budgets {
      try stores.budgets.setBudget(
        categoryID: try categoryID(budget.categoryName), amountMinor: budget.amountMinor)
    }

    // Pipeline rows go in one batch, as a statement or an inbox sync would, so
    // the near-duplicate merge and the transfer detector see each other.
    var drafts: [TransactionDraft] = []
    for row in dataset.rows {
      guard case .pipeline(let source, let senderDomain, let cardFragment) = row.route else { continue }
      drafts.append(
        TransactionDraft(
          date: row.date,
          descriptionText: row.narration,
          amountMinor: row.amountMinor,
          direction: row.direction,
          currencyCode: row.currencyCode,
          accountID: try accountID(row.accountKey),
          source: source,
          externalID: row.id,
          capturedAt: row.date,
          // Only an insert-time reason sets the flag here. A near duplicate is
          // flagged by the pipeline when it merges, so it is left unflagged.
          needsReview: reason(of: row) != nil,
          senderDomain: senderDomain,
          cardFragment: cardFragment,
          needsReviewReason: reason(of: row)
        ))
    }
    _ = try await stores.pipeline.ingest(drafts)

    for row in dataset.rows {
      guard case .manual = row.route else { continue }
      _ = try stores.transactions.add(
        ManualTransactionDraft(
          date: row.date,
          amountMinor: row.amountMinor,
          descriptionText: row.narration,
          direction: row.direction,
          categoryID: try row.categoryName.map(categoryID),
          accountID: try accountID(row.accountKey)))
    }

    // Last, so every rule re-applies across the rows above. Each create saves
    // and invalidates the Insights cache, so the Home screen reads the result.
    for rule in dataset.rules {
      let scope = RuleScope(
        direction: rule.direction,
        accountID: try accountID(rule.accountKey),
        minAmountMinor: rule.minAmountMinor,
        maxAmountMinor: rule.maxAmountMinor)
      try stores.rules.create(
        pattern: rule.pattern, categoryID: try categoryID(rule.categoryName), scope: scope)
    }
    return true
  }

  /// The reason the ingester gives. A near duplicate has none: the pipeline sets
  /// its flag at merge time, and that is the only flag it carries.
  private static func reason(of row: DemoRow) -> NeedsReviewReason? {
    if case .reason(let reason) = row.review { return reason }
    return nil
  }
}
#endif
