import Foundation
import NomiCore

@MainActor
public final class FakeBudgetStore: BudgetStore {
  public var storedBudgets: [Budget]

  public init(budgets: [Budget] = PreviewData.budgets) {
    self.storedBudgets = budgets
  }

  /// Refuses an amount outside `AmountRules` before changing anything, as the real store
  /// does (R8b). Zero is refused, not treated as removal: removal is `removeBudget` alone.
  public func setBudget(categoryID: UUID, amountMinor: Int) throws {
    guard AmountRules.isValidTransactionAmount(amountMinor) else {
      throw AmountValidationError.outOfRange(amountMinor: amountMinor)
    }
    if let existing = storedBudgets.first(where: { $0.categoryID == categoryID }) {
      existing.amountMinor = amountMinor
    } else {
      let budget = Budget(categoryID: categoryID, amountMinor: amountMinor)
      storedBudgets.append(budget)
    }
  }

  public func removeBudget(categoryID: UUID) throws {
    storedBudgets.removeAll { $0.categoryID == categoryID }
  }

  public func budgets() throws -> [Budget] {
    storedBudgets
  }
}
