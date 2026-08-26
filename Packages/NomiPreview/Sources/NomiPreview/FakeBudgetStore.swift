import Foundation
import NomiCore

@MainActor
public final class FakeBudgetStore: BudgetStore {
  public var storedBudgets: [Budget]

  public init(budgets: [Budget] = PreviewData.budgets) {
    self.storedBudgets = budgets
  }

  public func setBudget(categoryID: UUID, amountMinor: Int) throws {
    if amountMinor == 0 {
      try removeBudget(categoryID: categoryID)
      return
    }
    if let existing = storedBudgets.first(where: { $0.categoryID == categoryID }) {
      existing.amountMinor = amountMinor
    } else {
      storedBudgets.append(Budget(categoryID: categoryID, amountMinor: amountMinor))
    }
  }

  public func removeBudget(categoryID: UUID) throws {
    storedBudgets.removeAll { $0.categoryID == categoryID }
  }

  public func budgets() throws -> [Budget] {
    storedBudgets
  }
}
