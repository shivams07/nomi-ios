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
    let rows = transactions.filter { range.contains($0.date) }

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
        paletteSlot: category?.paletteSlot ?? 6,
        totalMinor: total,
        share: debit > 0 ? Double(total) / Double(debit) : 0
      )
    }.sorted { $0.totalMinor > $1.totalMinor }

    var byDay: [Date: Int] = [:]
    for row in rows where row.directionRaw == Direction.debit.rawValue {
      let day = calendar.startOfDay(for: row.date)
      byDay[day, default: 0] += row.amountMinor
    }
    let dayBuckets = byDay.map { DayBucket(id: $0.key, debitMinor: $0.value) }.sorted { $0.id < $1.id }

    var byMerchant: [String: (String, Int)] = [:]
    for row in rows where row.directionRaw == Direction.debit.rawValue {
      let key = row.normalizedDescription
      let label = row.merchantName ?? row.descriptionText
      let existing = byMerchant[key]?.1 ?? 0
      byMerchant[key] = (label, existing + row.amountMinor)
    }
    let topMerchants = byMerchant.map { MerchantTotal(id: $0.key, label: $0.value.0, totalMinor: $0.value.1) }
      .sorted { $0.totalMinor > $1.totalMinor }
      .prefix(5)

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
      needsReviewCount: rows.filter { $0.needsReview }.count,
      uncategorizedCount: rows.filter { $0.categoryID == nil }.count
    )
  }

  public func trend(months: Int) throws -> [MonthBucket] {
    let range = dateRange(for: .trailingMonths(months), calendar: calendar)
    let rows = transactions.filter { range.contains($0.date) }
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
          trackedBalanceMinor: credit - debit,
          transactionCount: rows.count,
          trackingSince: rows.map(\.date).min(),
          isArchived: account.isArchived
        )
      }
  }

  public func budgetProgress(year: Int, month: Int) throws -> [BudgetProgress] {
    let range = dateRange(for: .month(year: year, month: month), calendar: calendar)
    let periodKey = String(format: "%04d-%02d", year, month)
    return budgets.map { budget in
      let category = categories.first { $0.id == budget.categoryID }
      let spent = transactions
        .filter { range.contains($0.date) && $0.categoryID == budget.categoryID && $0.directionRaw == Direction.debit.rawValue }
        .reduce(0) { $0 + $1.amountMinor }
      return BudgetProgress(
        id: budget.categoryID,
        categoryName: category?.name ?? "Uncategorized",
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
}
