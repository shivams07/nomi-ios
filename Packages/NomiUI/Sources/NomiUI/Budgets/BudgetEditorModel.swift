import Foundation
import NomiCore
import Observation

/// The budget editor's state and actions, outside the view (T2a), so plain XCTest
/// can drive them with a spy store. The sheet owns one through `@State`. Save only
/// ever sets a budget; removal needs `requestRemove` and then `confirmRemove`.
@Observable @MainActor final class BudgetEditorModel {
  @ObservationIgnored let store: BudgetStore
  @ObservationIgnored let category: NomiCore.Category?
  @ObservationIgnored let currentAmountMinor: Int

  var amountText: String
  var selectedCategoryID: UUID?
  var errorMessage: String?
  var isConfirmingRemove = false
  /// Set by `requestRemove`, cleared by `cancelRemove` and by a confirmed removal.
  /// `confirmRemove` does nothing without it.
  @ObservationIgnored private var removeArmed = false

  init(store: BudgetStore, category: NomiCore.Category?, currentAmountMinor: Int) {
    self.store = store
    self.category = category
    self.currentAmountMinor = currentAmountMinor
    amountText = currentAmountMinor > 0 ? String(format: "%.2f", Double(currentAmountMinor) / 100) : ""
    selectedCategoryID = category?.id
  }

  var isCreating: Bool { category == nil }

  /// The Remove row is offered only for a category that already has a budget.
  var isExistingBudget: Bool { !isCreating && currentAmountMinor > 0 }

  var amountMinor: Int { EntryAmount.minorUnits(from: amountText) }

  var canSave: Bool {
    BudgetFormGate.isValid(categoryID: selectedCategoryID, amountMinor: amountMinor)
  }

  /// Keeps the amount field to what `EntryAmount` accepts, as the keypad types it.
  func amountDidChange(_ newValue: String) {
    let sanitized = EntryAmount.sanitizeInput(newValue)
    if sanitized != newValue { amountText = sanitized }
  }

  /// Sets the budget. Returns true when the caller should call `onSaved` and
  /// dismiss. Never removes a budget, whatever the amount.
  func save() -> Bool {
    do {
      guard try BudgetSaveAction.perform(categoryID: selectedCategoryID, amountMinor: amountMinor, store: store) else {
        return false
      }
      return true
    } catch {
      errorMessage = "Could not save this budget."
      return false
    }
  }

  func requestRemove() {
    removeArmed = true
    isConfirmingRemove = true
  }

  func cancelRemove() {
    removeArmed = false
  }

  /// Removes the category's budget only after `requestRemove`. Returns true when
  /// the caller should call `onSaved` and dismiss.
  func confirmRemove() -> Bool {
    guard removeArmed, let id = category?.id else { return false }
    removeArmed = false
    do {
      try store.removeBudget(categoryID: id)
      return true
    } catch {
      errorMessage = "Could not remove this budget."
      return false
    }
  }
}
