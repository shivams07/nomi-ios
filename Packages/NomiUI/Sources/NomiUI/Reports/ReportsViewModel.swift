import Foundation
import NomiCore

/// Every figure the Reports screen renders, derived once from a period's
/// `PeriodInsights` plus its trend buckets. Kept as a single `Equatable`
/// value — not scattered computed properties on the screen — specifically so
/// "switching basis recomputes every figure on screen" is assertable by
/// comparing two of these, not by eyeballing a rendered view (design's own
/// done-when wording).
struct ReportsViewModel: Equatable {
  let period: InsightPeriod
  let periodLabel: String
  let debitMinor: Int
  let creditMinor: Int
  let netMinor: Int
  let debitDelta: ReportsDelta.Result?
  let creditDelta: ReportsDelta.Result?
  let categories: [CategorySlice]
  let trend: [MonthBucket]
  let transactionCount: Int

  static func == (lhs: ReportsViewModel, rhs: ReportsViewModel) -> Bool {
    lhs.period == rhs.period
      && lhs.periodLabel == rhs.periodLabel
      && lhs.debitMinor == rhs.debitMinor
      && lhs.creditMinor == rhs.creditMinor
      && lhs.netMinor == rhs.netMinor
      && lhs.debitDelta == rhs.debitDelta
      && lhs.creditDelta == rhs.creditDelta
      && lhs.categories.map(\.id) == rhs.categories.map(\.id)
      && lhs.categories.map(\.totalMinor) == rhs.categories.map(\.totalMinor)
      && lhs.trend.map(\.id) == rhs.trend.map(\.id)
      && lhs.transactionCount == rhs.transactionCount
  }
}

enum ReportsViewModelBuilder {
  static func make(
    period: InsightPeriod,
    insights: PeriodInsights,
    trend: [MonthBucket],
    calendar: Calendar = .current
  ) -> ReportsViewModel {
    ReportsViewModel(
      period: period,
      periodLabel: ReportsPeriod.label(for: period, calendar: calendar),
      debitMinor: insights.debitMinor,
      creditMinor: insights.creditMinor,
      netMinor: insights.netMinor,
      debitDelta: ReportsDelta.compute(current: insights.debitMinor, prior: insights.priorDebitMinor),
      creditDelta: ReportsDelta.compute(current: insights.creditMinor, prior: insights.priorCreditMinor),
      categories: ReportsCategoryFold.foldToSevenSlots(insights.byCategory),
      trend: trend,
      transactionCount: insights.transactionCount
    )
  }
}
