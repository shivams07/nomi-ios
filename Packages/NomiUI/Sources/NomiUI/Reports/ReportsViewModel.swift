import Foundation
import NomiCore

/// Every figure the Insights screen renders for one period, derived from its
/// `PeriodInsights`. Kept as one `Equatable` value so "switching basis
/// recomputes every figure" is assertable by comparing two of these (R12b).
struct ReportsViewModel: Equatable {
  let period: InsightPeriod
  let debitMinor: Int
  let creditMinor: Int
  let priorDebitMinor: Int?
  let priorCreditMinor: Int?
  /// "₹14,855 less than Oct", or "Nothing spent in Oct to compare" when the
  /// prior period had none. `nil` with no prior period (F2a's copy).
  let debitComparison: String?
  let creditComparison: String?
  let categories: ReportsCategoryFold.Breakdown
  let uncategorizedCount: Int
  let transactionCount: Int
  let topMerchants: [MerchantTotal]

  static func == (lhs: ReportsViewModel, rhs: ReportsViewModel) -> Bool {
    lhs.period == rhs.period
      && lhs.debitMinor == rhs.debitMinor
      && lhs.creditMinor == rhs.creditMinor
      && lhs.priorDebitMinor == rhs.priorDebitMinor
      && lhs.priorCreditMinor == rhs.priorCreditMinor
      && lhs.debitComparison == rhs.debitComparison
      && lhs.creditComparison == rhs.creditComparison
      && lhs.categories == rhs.categories
      && lhs.uncategorizedCount == rhs.uncategorizedCount
      && lhs.transactionCount == rhs.transactionCount
      && lhs.topMerchants.map(\.id) == rhs.topMerchants.map(\.id)
      && lhs.topMerchants.map(\.totalMinor) == rhs.topMerchants.map(\.totalMinor)
      && lhs.topMerchants.map(\.count) == rhs.topMerchants.map(\.count)
  }
}

enum ReportsViewModelBuilder {
  /// `calendar` names the prior month. The screen passes the India calendar.
  static func make(period: InsightPeriod, insights: PeriodInsights, calendar: Calendar) -> ReportsViewModel {
    let priorLabel = NomiComparisonCopy.priorLabel(period: period, short: true, calendar: calendar)
    return ReportsViewModel(
      period: period,
      debitMinor: insights.debitMinor,
      creditMinor: insights.creditMinor,
      priorDebitMinor: insights.priorDebitMinor,
      priorCreditMinor: insights.priorCreditMinor,
      debitComparison: NomiComparisonCopy.line(
        kind: .spent,
        currentMinor: insights.debitMinor,
        priorMinor: insights.priorDebitMinor,
        priorLabel: priorLabel
      ),
      creditComparison: NomiComparisonCopy.line(
        kind: .income,
        currentMinor: insights.creditMinor,
        priorMinor: insights.priorCreditMinor,
        priorLabel: priorLabel
      ),
      categories: ReportsCategoryFold.breakdown(insights.byCategory),
      uncategorizedCount: insights.uncategorizedCount,
      transactionCount: insights.transactionCount,
      topMerchants: insights.topMerchants
    )
  }
}
