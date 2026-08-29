import Foundation
import NomiCore

/// A value-typed view of the fields the aggregates read.
///
/// Same device as `TransactionSnapshot` in the pipeline, for the same reason:
/// `swift test` cannot construct a SwiftData `@Model` in this CI at all (see
/// `NomiCore/Support/InMemoryModelContainer.swift`). Every number on the
/// dashboard is computed below this line, over these, where a test can run it.
/// `SwiftDataInsightsStore` fetches `Transaction` rows and maps them across.
public struct LedgerRow: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let date: Date
  public let amountMinor: Int
  public let directionRaw: String
  public let categoryID: UUID?
  public let accountID: UUID?
  public let normalizedDescription: String
  public let merchantName: String?
  public let descriptionText: String
  public let needsReview: Bool

  public init(
    id: UUID,
    date: Date,
    amountMinor: Int,
    directionRaw: String,
    categoryID: UUID?,
    accountID: UUID?,
    normalizedDescription: String,
    merchantName: String?,
    descriptionText: String,
    needsReview: Bool
  ) {
    self.id = id
    self.date = date
    self.amountMinor = amountMinor
    self.directionRaw = directionRaw
    self.categoryID = categoryID
    self.accountID = accountID
    self.normalizedDescription = normalizedDescription
    self.merchantName = merchantName
    self.descriptionText = descriptionText
    self.needsReview = needsReview
  }

  public var isDebit: Bool { directionRaw == Direction.debit.rawValue }
  public var isCredit: Bool { directionRaw == Direction.credit.rawValue }
}

public struct CategoryRef: Sendable, Equatable {
  public let id: UUID
  public let name: String
  public let paletteSlot: Int

  public init(id: UUID, name: String, paletteSlot: Int) {
    self.id = id
    self.name = name
    self.paletteSlot = paletteSlot
  }
}

public struct AccountRef: Sendable, Equatable {
  public let id: UUID
  public let displayName: String
  public let institution: String
  public let lastFour: String
  public let kindRaw: String
  public let isArchived: Bool

  public init(
    id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    isArchived: Bool
  ) {
    self.id = id
    self.displayName = displayName
    self.institution = institution
    self.lastFour = lastFour
    self.kindRaw = kindRaw
    self.isArchived = isArchived
  }
}

public struct BudgetRef: Sendable, Equatable {
  public let categoryID: UUID
  public let amountMinor: Int
  public let isEnabled: Bool

  public init(categoryID: UUID, amountMinor: Int, isEnabled: Bool) {
    self.categoryID = categoryID
    self.amountMinor = amountMinor
    self.isEnabled = isEnabled
  }
}

/// The real fetch-and-reduce (R14). Pure: no `ModelContext`, no `@Model`, no
/// clock beyond what it is handed.
///
/// Where the fake in `NomiPreview` and this disagree, the disagreement is
/// deliberate and noted at the site. Two are worth stating up front:
///
/// - **Every ordering here has a total tie-break.** The fake sorts by amount
///   alone and builds its groups in a `Dictionary`, so two categories with
///   equal spend come out in whatever order the hash gave that launch. That is
///   invisible in a six-row preview and is a list that reshuffles itself
///   between renders on real data.
/// - **`priorDebitMinor`/`priorCreditMinor` are populated.** The fake returns
///   `nil` for both, so `HeroTotalCard`'s delta has never rendered against
///   anything.
public enum InsightsAggregator {

  /// `"YYYY-MM"`. The single place this string is built in the app — it is the
  /// identity half of a `BudgetAlertLog` row, and a second implementation is
  /// how "once per category per month" quietly becomes "twice".
  public static func periodKey(year: Int, month: Int) -> String {
    String(format: "%04d-%02d", year, month)
  }

  /// The comparable window immediately before `period`, or `nil` where there
  /// isn't one.
  ///
  /// Every boundary is derived from `NomiCore.dateRange(for:)` — design §2.3
  /// makes that the sole owner of period arithmetic, and the March/April edge
  /// is exactly where a second implementation would disagree. `.trailingMonths`
  /// is the one case with no prior *period* to name, so its window is the same
  /// length taken back from the current window's start.
  public static func priorRange(
    for period: InsightPeriod,
    calendar: Calendar = .current,
    now: Date = Date()
  ) -> Range<Date>? {
    switch period {
    case .month(let year, let month):
      let priorMonth = month == 1 ? 12 : month - 1
      let priorYear = month == 1 ? year - 1 : year
      return dateRange(for: .month(year: priorYear, month: priorMonth), calendar: calendar, now: now)

    case .financialYear(let startingYear):
      return dateRange(for: .financialYear(startingYear: startingYear - 1), calendar: calendar, now: now)

    case .trailingMonths(let count):
      let current = dateRange(for: .trailingMonths(count), calendar: calendar, now: now)
      guard let start = calendar.date(byAdding: .month, value: -count, to: current.lowerBound) else {
        return nil
      }
      return start..<current.lowerBound

    case .allTime:
      return nil
    }
  }

  // MARK: - Insights

  public static func insights(
    period: InsightPeriod,
    rows: [LedgerRow],
    categories: [UUID: CategoryRef],
    priorRows: [LedgerRow]?,
    calendar: Calendar = .current
  ) -> PeriodInsights {
    let debit = sum(rows.filter(\.isDebit))
    let credit = sum(rows.filter(\.isCredit))
    let debits = rows.filter(\.isDebit)

    return PeriodInsights(
      period: period,
      debitMinor: debit,
      creditMinor: credit,
      netMinor: credit - debit,
      priorDebitMinor: priorRows.map { sum($0.filter(\.isDebit)) },
      priorCreditMinor: priorRows.map { sum($0.filter(\.isCredit)) },
      transactionCount: rows.count,
      byDay: byDay(debits, calendar: calendar),
      byCategory: byCategory(debits, categories: categories, debitTotal: debit),
      topMerchants: topMerchants(debits, limit: 5),
      needsReviewCount: rows.filter(\.needsReview).count,
      uncategorizedCount: rows.filter { $0.categoryID == nil }.count
    )
  }

  /// Debit only, one bucket per day that has spend, ascending. Days with no
  /// spend are absent rather than zero — the chart draws what it is given and
  /// a zero-filled month is a different chart.
  static func byDay(_ debits: [LedgerRow], calendar: Calendar) -> [DayBucket] {
    var totals: [Date: Int] = [:]
    for row in debits {
      totals[calendar.startOfDay(for: row.date), default: 0] += row.amountMinor
    }
    return totals
      .map { DayBucket(id: $0.key, debitMinor: $0.value) }
      .sorted { $0.id < $1.id }
  }

  /// Debit only. A nil `categoryID` folds into `Category.uncategorizedID` — a
  /// display sentinel, never a seeded row (`DefaultCategorySeed`) — and shows
  /// as "Uncategorized" at slot 6.
  ///
  /// `share` divides by the period's debit total, so the slices sum to 1 within
  /// rounding. A zero total yields zero shares rather than a NaN that would
  /// propagate into every bar width downstream.
  static func byCategory(
    _ debits: [LedgerRow],
    categories: [UUID: CategoryRef],
    debitTotal: Int
  ) -> [CategorySlice] {
    var totals: [UUID: Int] = [:]
    for row in debits {
      totals[row.categoryID ?? NomiCore.Category.uncategorizedID, default: 0] += row.amountMinor
    }

    return totals
      .map { categoryID, total -> CategorySlice in
        let category = categories[categoryID]
        return CategorySlice(
          id: categoryID,
          name: category?.name ?? "Uncategorized",
          paletteSlot: category?.paletteSlot ?? 6,
          totalMinor: total,
          share: debitTotal > 0 ? Double(total) / Double(debitTotal) : 0
        )
      }
      .sorted(by: descendingByAmount(\.totalMinor, then: \.name))
  }

  /// Debit only, grouped on `normalizedDescription` — the same key the dedupe
  /// path uses, so "SWIGGY*ORDER 8891" and "SWIGGY*ORDER 9002" roll up together
  /// rather than appearing as two merchants.
  static func topMerchants(_ debits: [LedgerRow], limit: Int) -> [MerchantTotal] {
    var totals: [String: (label: String, amount: Int)] = [:]
    for row in debits {
      let key = row.normalizedDescription
      let label = row.merchantName ?? row.descriptionText
      let running = totals[key]?.amount ?? 0
      // First label wins, so the rollup's name does not depend on fetch order.
      totals[key] = (totals[key]?.label ?? label, running + row.amountMinor)
    }

    return totals
      .map { MerchantTotal(id: $0.key, label: $0.value.label, totalMinor: $0.value.amount) }
      .sorted(by: descendingByAmount(\.totalMinor, then: \.label))
      .prefix(limit)
      .map { $0 }
  }

  // MARK: - Trend

  /// One bucket per calendar month present in `rows`, ascending. Both
  /// directions, unlike the dashboard's aggregates — the trend card draws
  /// spend against income.
  public static func trend(rows: [LedgerRow], calendar: Calendar = .current) -> [MonthBucket] {
    var totals: [Date: (debit: Int, credit: Int)] = [:]
    for row in rows {
      guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: row.date)) else {
        continue
      }
      var entry = totals[monthStart] ?? (0, 0)
      if row.isDebit {
        entry.debit += row.amountMinor
      } else {
        entry.credit += row.amountMinor
      }
      totals[monthStart] = entry
    }

    return totals
      .map { MonthBucket(id: $0.key, debitMinor: $0.value.debit, creditMinor: $0.value.credit) }
      .sorted { $0.id < $1.id }
  }

  // MARK: - Accounts

  /// All-time per account: balance, count, and the date tracking began.
  ///
  /// `trackedBalanceMinor` is credit minus debit **of what this app has seen**,
  /// which is not the bank's balance and is not claimed to be — the field is
  /// named for it. Rows with a nil `accountID` belong to no account and are
  /// counted nowhere here; they surface through `NeedsYouCard` instead.
  public static func accountSummaries(
    accounts: [AccountRef],
    rows: [LedgerRow],
    includeArchived: Bool
  ) -> [AccountSummary] {
    var byAccount: [UUID: [LedgerRow]] = [:]
    for row in rows {
      guard let accountID = row.accountID else { continue }
      byAccount[accountID, default: []].append(row)
    }

    return accounts
      .filter { includeArchived || !$0.isArchived }
      .map { account in
        let owned = byAccount[account.id] ?? []
        let credit = sum(owned.filter(\.isCredit))
        let debit = sum(owned.filter(\.isDebit))
        return AccountSummary(
          id: account.id,
          displayName: account.displayName,
          institution: account.institution,
          lastFour: account.lastFour,
          kindRaw: account.kindRaw,
          trackedBalanceMinor: credit - debit,
          transactionCount: owned.count,
          trackingSince: owned.map(\.date).min(),
          isArchived: account.isArchived
        )
      }
      .sorted { lhs, rhs in
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        return lhs.id.uuidString < rhs.id.uuidString
      }
  }

  // MARK: - Budgets

  /// The one owner of budget-progress arithmetic (design §2.2). `rows` must
  /// already be scoped to the month `periodKey` names; this does not re-derive
  /// the boundary.
  ///
  /// Disabled budgets are dropped, not rendered at zero: `Budget.isEnabled` is
  /// the model's own "this budget is not in force" and a bar for it would
  /// invite an alert for it.
  public static func budgetProgress(
    budgets: [BudgetRef],
    rows: [LedgerRow],
    categories: [UUID: CategoryRef],
    periodKey: String
  ) -> [BudgetProgress] {
    var spendByCategory: [UUID: Int] = [:]
    for row in rows where row.isDebit {
      guard let categoryID = row.categoryID else { continue }
      spendByCategory[categoryID, default: 0] += row.amountMinor
    }

    return budgets
      .filter { $0.isEnabled }
      .map { budget in
        let spent = spendByCategory[budget.categoryID] ?? 0
        let category = categories[budget.categoryID]
        return BudgetProgress(
          id: budget.categoryID,
          categoryName: category?.name ?? "Uncategorized",
          paletteSlot: category?.paletteSlot ?? 6,
          budgetMinor: budget.amountMinor,
          spentMinor: spent,
          // Unclamped, deliberately: `BudgetAlertEvaluator` reads `> 1` as over
          // budget and `NomiProgressBar` clamps its own fill. Clamping here
          // would make 140% and 100% indistinguishable to the alert.
          fraction: budget.amountMinor > 0 ? Double(spent) / Double(budget.amountMinor) : 0,
          periodKey: periodKey
        )
      }
      .sorted { lhs, rhs in
        if lhs.fraction != rhs.fraction { return lhs.fraction > rhs.fraction }
        return lhs.categoryName < rhs.categoryName
      }
  }

  // MARK: -

  private static func sum(_ rows: [LedgerRow]) -> Int {
    rows.reduce(0) { $0 + $1.amountMinor }
  }

  /// Amount descending, then a string ascending. The second key is not
  /// cosmetic: these lists are built from `Dictionary`, whose iteration order
  /// is seeded per process, so equal amounts would otherwise rank differently
  /// on each launch.
  private static func descendingByAmount<T>(
    _ amount: KeyPath<T, Int>,
    then label: KeyPath<T, String>
  ) -> (T, T) -> Bool {
    { lhs, rhs in
      let left = lhs[keyPath: amount]
      let right = rhs[keyPath: amount]
      if left != right { return left > right }
      return lhs[keyPath: label] < rhs[keyPath: label]
    }
  }
}
