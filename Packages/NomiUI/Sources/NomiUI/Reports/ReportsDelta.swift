import Foundation

/// Reports' prior-period comparison — the same shape as
/// `Dashboard/HeroTotalCard`'s `HeroDelta`, duplicated rather than imported
/// for the same file-boundary reason as `ReportsPeriod`. Generalised over
/// both `debitMinor` and `creditMinor`: the dashboard hero card only ever
/// compares spend, but Reports' notes call for "month-over-month comparison
/// from priorDebitMinor / priorCreditMinor" — both figures, not one.
enum ReportsDelta {
  struct Result: Equatable {
    let percent: Double
    let isIncrease: Bool
  }

  /// `nil` when there is no comparable prior period, or the prior period was
  /// zero (a percentage change against zero is undefined, not "infinite%").
  static func compute(current: Int, prior: Int?) -> Result? {
    guard let prior, prior != 0 else { return nil }
    let percent = Double(current - prior) / Double(abs(prior))
    return Result(percent: percent, isIncrease: current >= prior)
  }

  static func percentText(_ percent: Double) -> String {
    let whole = Int((abs(percent) * 100).rounded())
    return "\(whole)%"
  }
}
