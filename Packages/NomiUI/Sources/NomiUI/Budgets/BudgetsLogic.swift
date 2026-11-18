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

/// What saving the amount sheet should do. Save only ever sets a budget. Zero and
/// out-of-range amounts are `.invalid`, never a removal: removing a budget is the
/// editor's Remove row, which asks first (R8, X13). This is the one place that
/// decision is made.
enum BudgetSaveIntent: Equatable {
  case invalid
  case set(amountMinor: Int)

  static func resolve(amountMinor: Int) -> BudgetSaveIntent {
    AmountRules.isValidTransactionAmount(amountMinor) ? .set(amountMinor: amountMinor) : .invalid
  }
}

/// The hint shown under the amount when Save is disabled by the amount. R8b, ruling 5.
/// Silent for text still being typed ("" and a lone ".") and for any valid amount.
enum BudgetAmountHint {
  static let outOfRange = "Enter an amount from ₹0.01 to ₹1,00,00,00,000."
  static let tooPrecise = "Amounts can have at most two decimal places."

  static func text(for amountText: String, locale: Locale = .current) -> String? {
    guard !amountText.isEmpty else { return nil }
    switch AmountText.parse(amountText, locale: locale, allowNegative: false) {
    case .success(let value):
      // Only zero reaches here as an invalid value: the parser already caps the magnitude.
      return AmountRules.isValidTransactionAmount(value) ? nil : outOfRange
    case .failure(.outOfRange):
      return outOfRange
    case .failure(.tooManyFractionDigits):
      return tooPrecise
    case .failure(.notANumber):
      return nil
    }
  }
}

/// The budget editor's Save, as a decision a test can drive with a spy store. R8b.
/// Save only ever sets. It never calls `removeBudget`: removal is the Remove row's
/// confirmed action, which the View reaches separately.
enum BudgetSaveAction {
  /// Sets the budget and returns true, or changes nothing and returns false.
  @MainActor
  static func perform(categoryID: UUID?, amountMinor: Int, store: BudgetStore) throws -> Bool {
    guard let categoryID, case .set(let amount) = BudgetSaveIntent.resolve(amountMinor: amountMinor) else {
      return false
    }
    try store.setBudget(categoryID: categoryID, amountMinor: amount)
    return true
  }
}

/// The budget editor's Save gate: a category, and an amount that is a valid
/// transaction amount. Zero is not a budget, so it does not pass.
enum BudgetFormGate {
  static func isValid(categoryID: UUID?, amountMinor: Int) -> Bool {
    categoryID != nil && AmountRules.isValidTransactionAmount(amountMinor)
  }
}

/// The Budgets aggregate — and, per v5 §Home, the Home remaining-
/// budget card's source too (`DashboardWiring.budgetModule` wraps this),
/// which is why it lives here rather than nested in a view.
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

/// Screen-level rules for the Budgets page: when the nav "+" exists and the
/// caption that replaces it once every category is budgeted (SIMP §3 item 12).
enum BudgetsLogic {
  /// The nav "+" is shown only while some category has no budget yet.
  static func showsAddButton(unbudgetedCount: Int) -> Bool {
    unbudgetedCount > 0
  }

  static let everyCategoryBudgetedCaption = "Every category has a budget."
}

/// The confirmation copy for the editor's "Remove budget" row. The alert is
/// the one place this sentence lives.
enum BudgetRemoveConfirmation {
  static func message(categoryName: String) -> String {
    "\(categoryName) stops tracking against a monthly limit. Your transactions are not changed."
  }
}

/// The gauge card's centre label and percentages. The centre never prints a
/// bare absolute value under "Left to spend": past the limit it reads
/// "Over budget", so the number cannot be read as money still to spend.
enum BudgetGaugeText {
  static func centreCaption(remainingMinor: Int) -> String {
    remainingMinor >= 0 ? "Left to spend" : "Over budget"
  }

  /// Whole percent of budget used, for the visible "66% used" caption.
  static func percentUsed(fraction: Double) -> Int {
    Int((fraction * 100).rounded())
  }

  /// The same figure spoken, so the gauge is not read as a bare ratio
  /// (N10: "N percent of budget").
  static func spokenPercent(fraction: Double) -> String {
    "\(percentUsed(fraction: fraction)) percent of budget used"
  }
}

/// The spoken summary of one category tile. A tile is one button, so its
/// VoiceOver label carries the figures the caption and colour show, and says
/// "over" in words rather than leaving it to the red colour or the "!" glyph.
enum BudgetTileSpeech {
  static func label(name: String, spentMinor: Int, remainingMinor: Int, fraction: Double) -> String {
    let spent = NomiFormatters.amountString(minor: spentMinor)
    let caption = BudgetTileCaption.text(remainingMinor).text
    return "\(name), \(spent) spent, \(caption), \(BudgetGaugeText.spokenPercent(fraction: fraction))"
  }
}
