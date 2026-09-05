import Foundation
import NomiCore
import SwiftData

/// The real `InsightsStore` — the only aggregate query path in the app (R14).
///
/// Two rules, both from R14, and both structural rather than aspirational:
///
/// 1. **Every fetch carries a predicate scoped to the period.** SQLite filters;
///    Swift reduces what survives. The naive version — fetch everything, filter
///    in `map` — is visibly janky on the screen the backfill hands the user,
///    and the fake in `NomiPreview` is instant on six rows and will never show
///    it.
/// 2. **Results are cached per period and dropped on any write.**
///    `InsightsCache` holds them; `WriteCoordinator` clears it. A dashboard
///    re-renders many times per period selection and must not re-query for each.
///
/// The arithmetic itself is in `InsightsAggregator`, over value types. This
/// file is the fetch and the mapping. Its older comment said a `@Model` could
/// not be reached by a test here at all; that was measured wrong (PR #27) —
/// XCTest builds a container fine, and `RecentTransactionsTests` does.
///
/// The residual this comment used to record — `DashboardView` rendering five
/// recent rows off `transactions(in: .allTime)`, so the first call after each
/// write materialised the whole ledger — is fixed: it calls
/// `recentTransactions(limit:)`, which is a `fetchLimit`.
@MainActor
public final class SwiftDataInsightsStore: InsightsStore {
  private let context: ModelContext
  private let cache: InsightsCache
  private let calendar: Calendar
  private let now: () -> Date

  public init(
    context: ModelContext,
    cache: InsightsCache,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { Date() }
  ) {
    self.context = context
    self.cache = cache
    self.calendar = calendar
    self.now = now
  }

  public func insights(for period: InsightPeriod) throws -> PeriodInsights {
    try cache.value(for: .insights(period)) {
      let categories = try categoryMap()
      let rows = try ledgerRows(in: dateRange(for: period, calendar: calendar, now: now()))
      let priorRows = try InsightsAggregator
        .priorRange(for: period, calendar: calendar, now: now())
        .map { try ledgerRows(in: $0) }

      return InsightsAggregator.insights(
        period: period,
        rows: rows,
        categories: categories,
        priorRows: priorRows,
        calendar: calendar
      )
    }
  }

  public func trend(months: Int) throws -> [MonthBucket] {
    try cache.value(for: .trend(months: months)) {
      let rows = try ledgerRows(in: dateRange(for: .trailingMonths(months), calendar: calendar, now: now()))
      return InsightsAggregator.trend(rows: rows, calendar: calendar)
    }
  }

  /// The one aggregate with no period to scope by: `trackedBalanceMinor`,
  /// `transactionCount` and `trackingSince` are all-time per the contract, and
  /// no predicate narrows an all-time sum. Without a maintained rollup this is
  /// one full pass, so it leans entirely on the cache: once per write batch,
  /// never once per render. Naming it here rather than letting it read as an
  /// oversight of rule (1).
  public func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] {
    try cache.value(for: .accountSummaries(includeArchived: includeArchived)) {
      let accounts = try context.fetch(FetchDescriptor<Account>()).map {
        AccountRef(
          id: $0.id,
          displayName: $0.displayName,
          institution: $0.institution,
          lastFour: $0.lastFour,
          kindRaw: $0.kindRaw,
          isArchived: $0.isArchived
        )
      }
      let rows = try ledgerRows(in: nil)
      return InsightsAggregator.accountSummaries(
        accounts: accounts,
        rows: rows,
        includeArchived: includeArchived
      )
    }
  }

  public func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    try cache.value(for: .budgetProgress(year: year, month: month)) {
      let budgets = try context.fetch(FetchDescriptor<Budget>()).map {
        BudgetRef(categoryID: $0.categoryID, amountMinor: $0.amountMinor, isEnabled: $0.isEnabled)
      }
      let range = dateRange(for: .month(year: year, month: month), calendar: calendar, now: now())
      return InsightsAggregator.budgetProgress(
        budgets: budgets,
        rows: try ledgerRows(in: range),
        categories: try categoryMap(),
        periodKey: InsightsAggregator.periodKey(year: year, month: month)
      )
    }
  }

  public func transactions(in period: InsightPeriod) throws -> [Transaction] {
    try cache.value(for: .transactions(period)) {
      let range = dateRange(for: period, calendar: calendar, now: now())
      let lower = range.lowerBound
      let upper = range.upperBound
      var descriptor = FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> { $0.date >= lower && $0.date < upper },
        // Sorted in the store, not in Swift. Every consumer wants newest first
        // — the ledger, and `RecentRows.mostRecent` — and SQLite has the index.
        sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
      )
      descriptor.includePendingChanges = true
      return try context.fetch(descriptor)
    }
  }

  /// F2. `fetchLimit` in the store, not `prefix` in Swift - the point is that
  /// SQLite stops after `limit` rows rather than handing the whole ledger
  /// across for the caller to throw away. No date predicate: the sort is on
  /// `date` descending and the limit does the bounding.
  public func recentTransactions(limit: Int) throws -> [Transaction] {
    try cache.value(for: .recent(limit: limit)) {
      guard limit > 0 else { return [] }
      var descriptor = FetchDescriptor<Transaction>(
        sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
      )
      descriptor.fetchLimit = limit
      descriptor.includePendingChanges = true
      return try context.fetch(descriptor)
    }
  }

  // MARK: -

  /// `nil` range means all time and issues no date predicate at all — a
  /// `distantPast` bound would make SQLite compare every row against a
  /// constant it can never exclude on.
  private func ledgerRows(in range: Range<Date>?) throws -> [LedgerRow] {
    var descriptor: FetchDescriptor<Transaction>
    if let range {
      let lower = range.lowerBound
      let upper = range.upperBound
      descriptor = FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> { $0.date >= lower && $0.date < upper }
      )
    } else {
      descriptor = FetchDescriptor<Transaction>()
    }
    descriptor.includePendingChanges = true
    return try context.fetch(descriptor).map { LedgerRow($0) }
  }

  /// `uniquingKeysWith`, not `uniqueKeysWithValues`. CloudKit gives no
  /// cross-device uniqueness (R5) and `Category` syncs like everything else, so
  /// two rows can briefly share an id — and `uniqueKeysWithValues` traps on a
  /// duplicate key rather than returning an error. A crash on the dashboard
  /// because a second device is mid-sync is not a trade worth making for a
  /// tidier initialiser.
  private func categoryMap() throws -> [UUID: CategoryRef] {
    let categories = try context.fetch(FetchDescriptor<NomiCore.Category>())
    return Dictionary(
      categories.map { ($0.id, CategoryRef(id: $0.id, name: $0.name, paletteSlot: $0.paletteSlot)) },
      uniquingKeysWith: { first, _ in first }
    )
  }
}

extension LedgerRow {
  /// Confined to this file, like the pipeline's snapshot conversions: the pure
  /// aggregation code must never mention a `@Model` type or it stops being
  /// runnable under `swift test`.
  init(_ transaction: Transaction) {
    self.init(
      id: transaction.id,
      date: transaction.date,
      amountMinor: transaction.amountMinor,
      directionRaw: transaction.directionRaw,
      categoryID: transaction.categoryID,
      accountID: transaction.accountID,
      normalizedDescription: transaction.normalizedDescription,
      merchantName: transaction.merchantName,
      descriptionText: transaction.descriptionText,
      needsReview: transaction.needsReview
    )
  }
}
