import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// `BudgetEditorModel` with a spy store (T2a). Save only ever sets, and removal
/// needs a request and then a confirm. The kill list is in each test's comment.
@MainActor
final class BudgetEditorModelTests: XCTestCase {
  /// The budget the spy recorded through `setBudget`.
  struct BudgetSet: Equatable {
    let categoryID: UUID
    let amountMinor: Int
  }

  @MainActor
  private final class BudgetSpy: BudgetStore {
    private(set) var sets: [BudgetSet] = []
    private(set) var removals: [UUID] = []
    var failsSet = false
    var failsRemove = false

    struct Refused: Error {}

    func setBudget(categoryID: UUID, amountMinor: Int) throws {
      if failsSet { throw Refused() }
      sets.append(BudgetSet(categoryID: categoryID, amountMinor: amountMinor))
    }

    func removeBudget(categoryID: UUID) throws {
      if failsRemove { throw Refused() }
      removals.append(categoryID)
    }

    func budgets() throws -> [Budget] { [] }
  }

  private let category = NomiCore.Category(
    name: "Food", symbolName: "fork.knife", paletteSlot: 0, isSystem: false, sortIndex: 0)

  /// An edit-mode model for `category`, which has a budget of 5000.00.
  private func editModel(_ spy: BudgetSpy) -> BudgetEditorModel {
    BudgetEditorModel(store: spy, category: category, currentAmountMinor: 5000_00)
  }

  /// Save never removes a budget, whatever the amount. Only "45" is valid.
  /// Kills T2-M8: the mutant's else branch removes the category's budget.
  func testSaveNeverRemovesWhateverTheAmount() {
    let spy = BudgetSpy()
    let model = editModel(spy)

    for amountText in ["0", "", "-5", "1000000000.01", "45"] {
      model.amountText = amountText
      _ = model.save()
    }

    XCTAssertEqual(spy.removals, [])
    XCTAssertEqual(spy.sets.map(\.amountMinor), [45_00])
  }

  func testSaveFailureShowsCopyAndStays() {
    let spy = BudgetSpy()
    spy.failsSet = true
    let model = editModel(spy)
    model.amountText = "45"

    XCTAssertFalse(model.save())
    XCTAssertEqual(model.errorMessage, "Could not save this budget.")
  }

  /// Save at an amount that BudgetSaveAction refuses returns false, with no store
  /// call and no error copy.
  func testSaveRefusedAmountChangesNothing() {
    let spy = BudgetSpy()
    let model = editModel(spy)
    model.amountText = "0"

    XCTAssertFalse(model.save())
    XCTAssertEqual(spy.sets, [])
    XCTAssertNil(model.errorMessage)
  }

  func testRemoveAsksFirst() {
    let spy = BudgetSpy()
    let model = editModel(spy)

    model.requestRemove()

    XCTAssertTrue(model.isConfirmingRemove)
    XCTAssertEqual(spy.removals, [])
  }

  /// Without a request, confirming does nothing. Kills T2-M9.
  func testConfirmRemoveWithoutAskingDoesNothing() {
    let spy = BudgetSpy()
    let model = editModel(spy)

    XCTAssertFalse(model.confirmRemove())
    XCTAssertEqual(spy.removals, [])
  }

  /// One request removes that category once. A second confirm finds it disarmed.
  func testConfirmAfterAskingRemovesThatCategoryOnce() {
    let spy = BudgetSpy()
    let model = editModel(spy)
    model.requestRemove()

    XCTAssertTrue(model.confirmRemove())
    XCTAssertEqual(spy.removals, [category.id])
    XCTAssertFalse(model.confirmRemove())
    XCTAssertEqual(spy.removals, [category.id])
  }

  func testCancelRemoveDisarms() {
    let spy = BudgetSpy()
    let model = editModel(spy)
    model.requestRemove()

    model.cancelRemove()

    XCTAssertFalse(model.confirmRemove())
    XCTAssertEqual(spy.removals, [])
  }

  func testRemoveFailureShowsCopy() {
    let spy = BudgetSpy()
    spy.failsRemove = true
    let model = editModel(spy)
    model.requestRemove()

    XCTAssertFalse(model.confirmRemove())
    XCTAssertEqual(model.errorMessage, "Could not remove this budget.")
  }

  /// In create mode there is no category to remove, even after a request and a confirm.
  func testCreateModeCannotRemove() {
    let spy = BudgetSpy()
    let model = BudgetEditorModel(store: spy, category: nil, currentAmountMinor: 0)

    model.requestRemove()

    XCTAssertFalse(model.confirmRemove())
    XCTAssertEqual(spy.removals, [])
  }
}
