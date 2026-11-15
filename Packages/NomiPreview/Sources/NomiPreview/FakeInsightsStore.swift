import Foundation
import NomiCore

@MainActor
public final class FakeInsightsStore: InsightsStore {
  private let transactions: [Transaction]
  private let categories: [NomiCore.Category]
  private let accounts: [Account]
  private let budgets: [Budget]
  private let calendar = Calendar.current

  public init(
    transactions: [Transaction] = PreviewData.transactions,
    categories: [NomiCore.Category] = PreviewData.categories,
    accounts: [Account] = PreviewData.accounts,
    budgets: [Budget] = PreviewData.budgets
  ) {
    self.transactions = transactions
    self.categories = categories
    self.accounts = accounts
    self.budgets = budgets
  }

  public func insights(for period: InsightPeriod) throws -> PeriodInsights {
    let range = dateRange(for: period, calendar: calendar)
    let allRows = transactions.filter { range.contains($0.date) }
    // DEC-05, mirrored from InsightsAggregator: a transfer is in no spend,
    // income, category, merchant or uncategorised figure. It stays in the
    // review count.
    let rows = allRows.filter { !$0.isTransfer }

    let debit = rows.filter { $0.directionRaw == Direction.debit.rawValue }.reduce(0) { $0 + $1.amountMinor }
    let credit = rows.filter { $0.directionRaw == Direction.credit.rawValue }.reduce(0) { $0 + $1.amountMinor }

    var byCategory: [UUID: Int] = [:]
    for row in rows where row.directionRaw == Direction.debit.rawValue {
      byCategory[row.categoryID ?? NomiCore.Category.uncategorizedID, default: 0] += row.amountMinor
    }
    let categorySlices: [CategorySlice] = byCategory.map { categoryID, total in
      let category = categories.first { $0.id == categoryID }
      return CategorySlice(
        id: categoryID,
        name: category?.name ?? "Uncategorized",
        symbolName: category?.symbolName ?? "questionmark",
        paletteSlot: category?.paletteSlot ?? 6,
        totalMinor: total,
        share: debit > 0 ? Double(total) / Double(debit) : 0
      )
    }.sorted { $0.totalMinor > $1.totalMinor }

    // I-10, mirrored from `InsightsAggregator.byDay` over the same rows, so a
    // preview's sparkline is the store's sparkline.
    let dayBuckets = fakeByDay(allRows)

    var byMerchant: [String: (label: String, total: Int, count: Int)] = [:]
    for row in rows where row.directionRaw == Direction.debit.rawValue {
      let key = row.normalizedDescription
      let label = row.merchantName ?? row.descriptionText
      let existing = byMerchant[key]
      byMerchant[key] = (
        existing?.label ?? label,
        (existing?.total ?? 0) + row.amountMinor,
        (existing?.count ?? 0) + 1
      )
    }
    let topMerchants = byMerchant.map {
      MerchantTotal(id: $0.key, label: $0.value.label, totalMinor: $0.value.total, count: $0.value.count)
    }
      .sorted { $0.totalMinor > $1.totalMinor }
      .prefix(5)

    // I-10. The like-for-like prior window, the same cut the store makes, so the
    // prior-period sparkline lines up day for day with this one.
    let priorBuckets: [DayBucket]
    if let window = fakePriorRange(for: period, now: Date()) {
      priorBuckets = fakeByDay(transactions.filter { window.contains($0.date) })
    } else {
      priorBuckets = []
    }

    // The aggregator's order, id last, so a preview lists categories the way the
    // app does.
    let badges = categories
      .sorted { lhs, rhs in
        if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id.uuidString < rhs.id.uuidString
      }
      .map { CategoryBadge(id: $0.id, name: $0.name, symbolName: $0.symbolName, paletteSlot: $0.paletteSlot) }

    return PeriodInsights(
      period: period,
      debitMinor: debit,
      creditMinor: credit,
      netMinor: credit - debit,
      priorDebitMinor: nil,
      priorCreditMinor: nil,
      transactionCount: rows.count,
      byDay: dayBuckets,
      byCategory: categorySlices,
      topMerchants: Array(topMerchants),
      needsReviewCount: allRows.filter { $0.needsReview }.count,
      uncategorizedCount: rows.filter { $0.categoryID == nil }.count,
      categories: badges,
      priorByDay: priorBuckets
    )
  }

  /// I-10, as `InsightsAggregator.byDay` over `isCountedSpend` rows: INR, not a
  /// transfer, debit and credit summed apart, one bucket per day with a counted
  /// row, ascending. Written out again because NomiPreview does not see NomiApp.
  private func fakeByDay(_ rows: [Transaction]) -> [DayBucket] {
    var totals: [Date: (debit: Int, credit: Int)] = [:]
    for row in rows where !row.isTransfer && row.currencyCode == "INR" {
      let day = calendar.startOfDay(for: row.date)
      var entry = totals[day] ?? (0, 0)
      if row.directionRaw == Direction.debit.rawValue {
        entry.debit += row.amountMinor
      } else if row.directionRaw == Direction.credit.rawValue {
        entry.credit += row.amountMinor
      }
      totals[day] = entry
    }
    return totals
      .map { DayBucket(id: $0.key, debitMinor: $0.value.debit, creditMinor: $0.value.credit) }
      .sorted { $0.id < $1.id }
  }

  /// `InsightsAggregator.priorRange`, written out again for the same reason as
  /// `fakeTrendMonths`: the boundary is `dateRange`, the like-for-like cut is the
  /// same arithmetic. `nil` for `.allTime`.
  private func fakePriorRange(for period: InsightPeriod, now: Date) -> Range<Date>? {
    switch period {
    case .month(let year, let month):
      let priorMonth = month == 1 ? 12 : month - 1
      let priorYear = month == 1 ? year - 1 : year
      let prior = dateRange(for: .month(year: priorYear, month: priorMonth), calendar: calendar, now: now)
      return fakeLikeForLike(
        current: dateRange(for: period, calendar: calendar, now: now), prior: prior, now: now)

    case .financialYear(let startingYear):
      let prior = dateRange(for: .financialYear(startingYear: startingYear - 1), calendar: calendar, now: now)
      return fakeLikeForLike(
        current: dateRange(for: period, calendar: calendar, now: now), prior: prior, now: now)

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

  /// `prior` cut to as many days as `current` has elapsed by `now`, when
  /// `current` contains `now`; otherwise the whole of `prior`.
  private func fakeLikeForLike(current: Range<Date>, prior: Range<Date>, now: Date) -> Range<Date> {
    guard current.contains(now) else { return prior }
    let today = calendar.startOfDay(for: now)
    let daysSinceStart = calendar.dateComponents([.day], from: current.lowerBound, to: today).day ?? 0
    let cutoff = calendar.date(byAdding: .day, value: daysSinceStart + 1, to: prior.lowerBound) ?? prior.upperBound
    return prior.lowerBound..<min(cutoff, prior.upperBound)
  }

  public func trend(months: Int) throws -> [MonthBucket] {
    let range = dateRange(for: .trailingMonths(months), calendar: calendar)
    // DEC-05: a transfer is neither side of the trend.
    let rows = transactions.filter { range.contains($0.date) && !$0.isTransfer }
    var byMonth: [Date: (Int, Int)] = [:]
    for row in rows {
      guard let monthStart = calendar.date(
        from: calendar.dateComponents([.year, .month], from: row.date)
      ) else { continue }
      var entry = byMonth[monthStart] ?? (0, 0)
      if row.directionRaw == Direction.debit.rawValue {
        entry.0 += row.amountMinor
      } else {
        entry.1 += row.amountMinor
      }
      byMonth[monthStart] = entry
    }
    return byMonth.map { MonthBucket(id: $0.key, debitMinor: $0.value.0, creditMinor: $0.value.1) }
      .sorted { $0.id < $1.id }
  }

  /// R12a. Same contract as `SwiftDataInsightsStore.monthlyTrend(for:)`. This
  /// target depends on NomiCore only, so `InsightsAggregator` is not visible
  /// here, and the month list and the zero-fill are written out again below.
  /// INR and non-transfer rows only, as the real trend counts them.
  public func monthlyTrend(for period: InsightPeriod) throws -> [MonthBucket] {
    let now = Date()
    let months = fakeTrendMonths(for: period, now: now)
    guard let first = months.first, let last = months.last else { return [] }
    let endOfLast = calendar.date(byAdding: .month, value: 1, to: last) ?? last
    let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? endOfLast
    let upper = min(endOfLast, startOfTomorrow)
    let rows = transactions.filter {
      $0.date >= first && $0.date < upper && !$0.isTransfer && $0.currencyCode == "INR"
    }
    var byMonth: [Date: (debit: Int, credit: Int)] = [:]
    for row in rows {
      guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: row.date)) else {
        continue
      }
      var entry = byMonth[monthStart] ?? (0, 0)
      if row.directionRaw == Direction.debit.rawValue {
        entry.debit += row.amountMinor
      } else {
        entry.credit += row.amountMinor
      }
      byMonth[monthStart] = entry
    }
    return months.map { month in
      let entry = byMonth[month] ?? (0, 0)
      return MonthBucket(id: month, debitMinor: entry.debit, creditMinor: entry.credit)
    }
  }

  /// The month starts for `period`, as `InsightsAggregator.trendMonths` gives them.
  private func fakeTrendMonths(for period: InsightPeriod, now: Date) -> [Date] {
    let first: Int
    let count: Int
    switch period {
    case .month(let year, let month):
      first = year * 12 + month - 1 - 5
      count = 6
    case .financialYear(let startingYear):
      first = startingYear * 12 + 3
      count = 12
    case .trailingMonths(let months):
      count = max(months, 1)
      let parts = calendar.dateComponents([.year, .month], from: now)
      first = (parts.year ?? 0) * 12 + (parts.month ?? 1) - 1 - (count - 1)
    case .allTime:
      return []
    }
    return (first..<(first + count)).compactMap { index -> Date? in
      guard let start = calendar.date(from: DateComponents(year: index / 12, month: index % 12 + 1, day: 1)) else {
        return nil
      }
      return start <= now ? start : nil
    }
  }

  public func accountSummaries(includeArchived: Bool) throws -> [AccountSummary] {
    accounts
      .filter { includeArchived || !$0.isArchived }
      .map { account in
        let rows = transactions.filter { $0.accountID == account.id }
        let credit = rows.filter { $0.directionRaw == Direction.credit.rawValue }.reduce(0) { $0 + $1.amountMinor }
        let debit = rows.filter { $0.directionRaw == Direction.debit.rawValue }.reduce(0) { $0 + $1.amountMinor }
        return AccountSummary(
          id: account.id,
          displayName: account.displayName,
          institution: account.institution,
          lastFour: account.lastFour,
          kindRaw: account.kindRaw,
          // Opening balance included, as `InsightsAggregator` does it. A fake
          // that left it out would give the edit sheet's preview a balance
          // that ignores the field the sheet was added to set.
          trackedBalanceMinor: (account.openingBalanceMinor ?? 0) + credit - debit,
          transactionCount: rows.count,
          trackingSince: rows.map(\.date).min(),
          isArchived: account.isArchived,
          // Carried through for the same reason the sum above includes it: a
          // preview of the edit sheet must show the field already populated.
          openingBalanceMinor: account.openingBalanceMinor
        )
      }
  }

  public func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    let range = dateRange(for: .month(year: year, month: month), calendar: calendar)
    let periodKey = String(format: "%04d-%02d", year, month)
    return budgets.map { budget in
      let category = categories.first { $0.id == budget.categoryID }
      let spent = transactions
        .filter {
          range.contains($0.date) && !$0.isTransfer && $0.categoryID == budget.categoryID
            && $0.directionRaw == Direction.debit.rawValue
        }
        .reduce(0) { $0 + $1.amountMinor }
      return BudgetProgress(
        id: budget.categoryID,
        categoryName: category?.name ?? "Uncategorized",
        symbolName: category?.symbolName ?? "questionmark",
        paletteSlot: category?.paletteSlot ?? 6,
        budgetMinor: budget.amountMinor,
        spentMinor: spent,
        fraction: budget.amountMinor > 0 ? Double(spent) / Double(budget.amountMinor) : 0,
        periodKey: periodKey
      )
    }
  }

  public func transactions(in period: InsightPeriod) throws -> [Transaction] {
    let range = dateRange(for: period, calendar: calendar)
    return transactions.filter { range.contains($0.date) }
  }

  public func recentTransactions(limit: Int) throws -> [Transaction] {
    Array(transactions.sorted { $0.date > $1.date }.prefix(max(0, limit)))
  }

  /// I-10. The answer `SwiftDataInsightsStore.unassignedTransactions()` gives on
  /// the same rows: no account, newest first, transfers included.
  public func unassignedTransactions() throws -> [Transaction] {
    transactions.filter { $0.accountID == nil }.sorted { $0.date > $1.date }
  }
}
