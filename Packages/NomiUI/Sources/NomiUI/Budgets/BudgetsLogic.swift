import Foundation
import NomiCore

/// The current calendar period `InsightsStore.budgetProgress(year:month:)`
/// should be queried for. Pulled out as a pure function — same reasoning as
/// `DashboardPeriod` — so "today" doesn't have to be threaded through a live
/// `Date()` call to be testable.
enum BudgetPeriod {
  static func current(from date: Date, calendar: Calendar = .current) -> (year: Int, month: Int) {
    let components = calendar.dateComponents([.year, .month], from: date)
    return (components.year ?? 1970, components.month ?? 1)
  }
}

/// Whether a row needs the >=90% treatment. Kept separate from
/// `NomiProgressBar`'s own (private) threshold check — the bar's colour
/// switch and the row's non-colour distinction both key off the same 0.9,
/// declared once here rather than copied into each.
enum BudgetRowEmphasis {
  static func isAtOrAboveThreshold(_ progress: BudgetProgress) -> Bool {
    progress.fraction >= 0.9
  }
}

/// What saving the amount sheet should do. Setting 0 is presented as removal,
/// never as a zero budget the user would then read as "infinitely over" —
/// this is the one place that decision is made, so the sheet's Save button
/// and its confirmation copy can't drift from each other.
enum BudgetSaveIntent: Equatable {
  case remove
  case set(amountMinor: Int)

  static func resolve(amountMinor: Int) -> BudgetSaveIntent {
    amountMinor == 0 ? .remove : .set(amountMinor: amountMinor)
  }
}

/// The budget editor's Save gate. Amount has no lower bound beyond zero —
/// zero is a valid, meaningful input (remove) — so only a category selection
/// is required, unlike `EntrySaveGate` which requires a positive amount.
enum BudgetFormGate {
  static func isValid(categoryID: UUID?) -> Bool {
    categoryID != nil
  }
}

/// The Budgets screen's aggregate — and, per v5 §Home, the Home remaining-
/// budget card's source too (`DashboardWiring.budgetModule` wraps this),
/// which is why it lives here rather than nested in `BudgetsScreen`.
enum BudgetTotals {
  struct Totals: Equatable {
    let budgetMinor: Int
    let spentMinor: Int
    let remainingMinor: Int
    let fraction: Double
  }

  /// `nil` for `[]` — a zero-budgets month has no totals to show, distinct
  /// from a budgeted month that happens to sum to zero.
  static func compute(_ progress: [BudgetProgress]) -> Totals? {
    guard !progress.isEmpty else { return nil }
    let budgetMinor = progress.reduce(0) { $0 + $1.budgetMinor }
    let spentMinor = progress.reduce(0) { $0 + $1.spentMinor }
    return Totals(
      budgetMinor: budgetMinor,
      spentMinor: spentMinor,
      remainingMinor: budgetMinor - spentMinor,
      fraction: budgetMinor == 0 ? 0 : Double(spentMinor) / Double(budgetMinor)
    )
  }
}

/// Days remaining in the current month, inclusive of today — the gauge
/// card's "Days left" figure.
enum BudgetDaysLeft {
  static func remaining(from date: Date, calendar: Calendar = .current) -> Int {
    guard let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count else { return 0 }
    let today = calendar.component(.day, from: date)
    return daysInMonth - today + 1
  }
}

/// Whether spend is tracking under, on, over or past pace for the month —
/// the pace card and Home's remaining-budget card (M2) both read the same
/// four strings off `line(overByMinor:)` so they can never disagree.
enum BudgetPace {
  enum Pace: Equatable {
    case under
    case onPace
    case ahead
    case overBudget

    func line(overByMinor: Int) -> String {
      switch self {
      case .under: return "Well under pace. You've built a cushion."
      case .onPace: return "On pace."
      case .ahead: return "Ahead of pace. Slow down to land under budget."
      case .overBudget: return "Over budget by \(NomiFormatters.amountString(minor: overByMinor))."
      }
    }
  }

  static func assess(spentFraction: Double, elapsedFraction: Double) -> Pace {
    if spentFraction >= 1 { return .overBudget }
    if spentFraction > elapsedFraction + 0.10 { return .ahead }
    if spentFraction < elapsedFraction - 0.10 { return .under }
    return .onPace
  }
}

/// A budget tile's caption — "₹3,000 left" or "₹600 over" — and `isOver`,
/// which the tile uses to pick `overBudget` for the caption's colour. The
/// ≥90% emphasis glyph/weight is `BudgetRowEmphasis`'s own separate call;
/// this only decides the caption text and its colour.
enum BudgetTileCaption {
  static func text(_ remainingMinor: Int) -> (text: String, isOver: Bool) {
    remainingMinor >= 0
      ? ("\(NomiFormatters.amountString(minor: remainingMinor)) left", false)
      : ("\(NomiFormatters.amountString(minor: -remainingMinor)) over", true)
  }
}
