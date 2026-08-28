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
