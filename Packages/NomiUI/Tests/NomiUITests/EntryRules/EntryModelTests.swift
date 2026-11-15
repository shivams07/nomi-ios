import Foundation
import NomiCore
import XCTest

@testable import NomiUI

/// Records every write the entry model makes and answers the hint reads from
/// fixed values. It stands in for `TransactionStore` through the narrow
/// `EntryTransactionWriting` protocol, so no container is needed.
@MainActor
private final class EntryWriteSpy: EntryTransactionWriting {
  var lastUsedAccount: UUID?
  var lastUsedCategory: UUID?
  var suggestions: [UUID] = []
  var failAdd = false
  var failTransfer = false

  private(set) var addDrafts: [ManualTransactionDraft] = []
  private(set) var transfers: [TransferCall] = []
  private(set) var suggestionLimits: [Int] = []

  struct TransferCall: Equatable {
    let amountMinor: Int
    let fromAccountID: UUID
    let toAccountID: UUID
    let note: String?
  }

  enum Refusal: Error { case refused }

  func add(_ draft: ManualTransactionDraft) throws -> Transaction {
    if failAdd { throw Refusal.refused }
    addDrafts.append(draft)
    return Transaction()
  }

  func addTransfer(
    amountMinor: Int, date: Date, fromAccountID: UUID, toAccountID: UUID, note: String?
  ) throws -> (Transaction, Transaction) {
    if failTransfer { throw Refusal.refused }
    transfers.append(
      TransferCall(amountMinor: amountMinor, fromAccountID: fromAccountID, toAccountID: toAccountID, note: note))
    return (Transaction(), Transaction())
  }

  func lastUsedAccountID() -> UUID? { lastUsedAccount }

  func lastUsedCategoryID() -> UUID? { lastUsedCategory }

  func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID] {
    suggestionLimits.append(limit)
    return suggestions
  }
}

@MainActor
final class EntryModelTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func account(_ name: String, archived: Bool = false) -> EntryAccountOption {
    EntryAccountOption(id: UUID(), displayName: name, isArchived: archived)
  }

  private func category(_ name: String) -> EntryCategoryOption {
    EntryCategoryOption(id: UUID(), name: name, symbolName: "tag", paletteSlot: 0)
  }

  private func makeModel(
    spy: EntryWriteSpy? = nil,
    accounts: [EntryAccountOption] = [],
    categories: [EntryCategoryOption] = [],
    suggestionDelay: Duration = .zero
  ) -> EntryModel {
    EntryModel(
      store: spy ?? EntryWriteSpy(),
      accounts: accounts,
      categories: categories,
      now: now,
      suggestionDelay: suggestionDelay
    )
  }

  // MARK: - Defaults

  func testLastUsedAccountWinsWhenItIsStillActive() {
    let first = account("HDFC")
    let second = account("ICICI")
    let spy = EntryWriteSpy()
    spy.lastUsedAccount = second.id

    let model = makeModel(spy: spy, accounts: [first, second])

    XCTAssertEqual(model.accountID, second.id)
  }

  func testWithNoLastUsedAccountTheSingleActiveAccountIsPreselected() {
    let only = account("HDFC")

    let model = makeModel(accounts: [only])

    XCTAssertEqual(model.accountID, only.id)
  }

  func testWithNoLastUsedAccountAndTwoActiveAccountsNothingIsPreselected() {
    let model = makeModel(accounts: [account("HDFC"), account("ICICI")])

    XCTAssertNil(model.accountID)
  }

  /// An archived account can be the last one used. It is not offered any more,
  /// so the entry falls back to the single active account instead of naming it.
  func testAnArchivedLastUsedAccountFallsBackToTheRule() {
    let active = account("HDFC")
    let archived = account("Old card", archived: true)
    let spy = EntryWriteSpy()
    spy.lastUsedAccount = archived.id

    let model = makeModel(spy: spy, accounts: [active, archived])

    XCTAssertEqual(model.accountID, active.id)
  }

  func testLastUsedCategoryIsPrefilled() {
    let food = category("Food")
    let spy = EntryWriteSpy()
    spy.lastUsedCategory = food.id

    let model = makeModel(spy: spy, categories: [food])

    XCTAssertEqual(model.categoryID, food.id)
  }

  /// A last-used category that has since been deleted must not be prefilled,
  /// or Save would write a category id the picker cannot show.
  func testAStaleLastUsedCategoryIsNotPrefilled() {
    let spy = EntryWriteSpy()
    spy.lastUsedCategory = UUID()

    let model = makeModel(spy: spy, categories: [category("Food")])

    XCTAssertNil(model.categoryID)
  }

  // MARK: - Kinds and save title

  func testSpentIsTheDefaultKind() {
    XCTAssertEqual(makeModel().kind, .spent)
  }

  func testTheTransferKindIsOfferedOnlyWhenThereIsAnAccount() {
    XCTAssertEqual(makeModel().availableKinds, [.spent, .income])
    XCTAssertEqual(makeModel(accounts: [account("HDFC")]).availableKinds, [.spent, .income, .transfer])
  }

  func testSaveTitleWithoutACategory() {
    let model = makeModel()
    model.amountText = "360"

    XCTAssertEqual(model.saveTitle, "Save ₹360.00")
  }

  func testSaveTitleNamesTheCategory() {
    let food = category("Eating out")
    let model = makeModel(categories: [food])
    model.amountText = "360"
    model.categoryID = food.id

    XCTAssertEqual(model.saveTitle, "Save ₹360.00 to Eating out")
  }

  func testSaveTitleForATransfer() {
    let model = makeModel(accounts: [account("HDFC"), account("ICICI")])
    model.kind = .transfer
    model.amountText = "360"

    XCTAssertEqual(model.saveTitle, "Save transfer of ₹360.00")
  }

  // MARK: - Save writes

  /// Fixture: spent, 360, "Blue Tokai", note "Morning". One debit row on the
  /// chosen account, amount 36000 paise, the category and note as typed.
  func testSpentSavesOneDebitRowWithPayeeAndNote() {
    let hdfc = account("HDFC")
    let food = category("Eating out")
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy, accounts: [hdfc, account("ICICI")], categories: [food])
    model.accountID = hdfc.id
    model.categoryID = food.id
    model.amountText = "360"
    model.payee = "  Blue Tokai  "
    model.note = "Morning"

    XCTAssertTrue(model.save())

    XCTAssertEqual(spy.addDrafts.count, 1)
    XCTAssertEqual(spy.transfers.count, 0)
    let draft = spy.addDrafts[0]
    XCTAssertEqual(draft.amountMinor, 36_000)
    XCTAssertEqual(draft.direction, .debit)
    XCTAssertEqual(draft.descriptionText, "Blue Tokai")
    XCTAssertEqual(draft.accountID, hdfc.id)
    XCTAssertEqual(draft.categoryID, food.id)
    XCTAssertEqual(draft.note, "Morning")
  }

  /// Fixture: income, 1250.5, "Salary". One credit row, amount 125050 paise.
  func testIncomeSavesOneCreditRow() {
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy)
    model.kind = .income
    model.amountText = "1250.5"
    model.payee = "Salary"

    XCTAssertTrue(model.save())

    XCTAssertEqual(spy.addDrafts.count, 1)
    XCTAssertEqual(spy.addDrafts[0].amountMinor, 125_050)
    XCTAssertEqual(spy.addDrafts[0].direction, .credit)
    XCTAssertEqual(spy.addDrafts[0].descriptionText, "Salary")
  }

  /// Fixture: transfer, 500, HDFC to ICICI, note "Card bill". One transfer call
  /// and no plain add.
  func testTransferCallsAddTransferOnceAndNeverAdd() {
    let hdfc = account("HDFC")
    let icici = account("ICICI")
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy, accounts: [hdfc, icici])
    model.kind = .transfer
    model.accountID = hdfc.id
    model.toAccountID = icici.id
    model.amountText = "500"
    model.note = "Card bill"

    XCTAssertTrue(model.save())

    XCTAssertEqual(spy.addDrafts.count, 0)
    XCTAssertEqual(
      spy.transfers,
      [EntryWriteSpy.TransferCall(amountMinor: 50_000, fromAccountID: hdfc.id, toAccountID: icici.id, note: "Card bill")]
    )
  }

  /// Fixture: transfer with from == to. Save is refused, nothing is written.
  func testTransferFromAnAccountToItselfIsRefusedAndWritesNothing() {
    let hdfc = account("HDFC")
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy, accounts: [hdfc, account("ICICI")])
    model.kind = .transfer
    model.accountID = hdfc.id
    model.toAccountID = hdfc.id
    model.amountText = "500"

    XCTAssertFalse(model.canSave)
    XCTAssertEqual(model.transferCaption, "Choose two different accounts")
    XCTAssertFalse(model.save())
    XCTAssertEqual(spy.transfers.count, 0)
    XCTAssertEqual(spy.addDrafts.count, 0)
  }

  func testTransferNeedsBothAccounts() {
    let model = makeModel(accounts: [account("HDFC"), account("ICICI")])
    model.kind = .transfer
    model.amountText = "500"
    model.accountID = nil
    model.toAccountID = nil

    XCTAssertFalse(model.canSave)
    XCTAssertEqual(model.transferCaption, "Choose two different accounts")
  }

  /// Payee is optional: a blank payee saves with an empty description, and the
  /// list shows "Manual entry" for it.
  func testAnEmptyPayeeIsAllowed() {
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy)
    model.amountText = "40"

    XCTAssertTrue(model.save())

    XCTAssertEqual(spy.addDrafts.first?.descriptionText, "")
  }

  /// A refused write keeps the sheet's fields and sets the error the alert shows.
  func testAFailedSaveKeepsTheEntryAndSetsTheError() {
    let spy = EntryWriteSpy()
    spy.failAdd = true
    let model = makeModel(spy: spy)
    model.amountText = "360"
    model.payee = "Blue Tokai"

    XCTAssertFalse(model.save())

    XCTAssertEqual(model.errorMessage, "Could not save the transaction.")
    XCTAssertEqual(model.amountText, "360")
    XCTAssertEqual(model.payee, "Blue Tokai")
  }

  func testAFailedTransferKeepsTheEntryAndSetsTheError() {
    let spy = EntryWriteSpy()
    spy.failTransfer = true
    let hdfc = account("HDFC")
    let icici = account("ICICI")
    let model = makeModel(spy: spy, accounts: [hdfc, icici])
    model.kind = .transfer
    model.accountID = hdfc.id
    model.toAccountID = icici.id
    model.amountText = "500"

    XCTAssertFalse(model.save())

    XCTAssertEqual(model.errorMessage, "Could not save the transaction.")
    XCTAssertEqual(model.accountID, hdfc.id)
  }

  /// Save is disabled until the amount is positive and valid. Only the amount
  /// gates a spent or income entry.
  func testSaveIsDisabledUntilTheAmountIsValid() {
    let model = makeModel()

    model.amountText = ""
    XCTAssertFalse(model.canSave)
    model.amountText = "0"
    XCTAssertFalse(model.canSave)
    model.amountText = "1.999"
    XCTAssertFalse(model.canSave)
    model.amountText = "1"
    XCTAssertTrue(model.canSave)
  }

  func testTheAmountTextKeepsOnlyDigitsAndOneSeparator() {
    let model = makeModel()

    model.amountText = "12a.5.6"

    XCTAssertEqual(model.amountText, "12.56")
  }

  // MARK: - Suggestions

  /// The suggestions are asked for with limit 3, and a store that returns more
  /// is still held to three.
  func testSuggestionsAreAskedForThreeAndHeldToThree() {
    let categories = (0..<5).map { _ in category("c") }
    let spy = EntryWriteSpy()
    spy.suggestions = categories.map(\.id)
    let model = makeModel(spy: spy, categories: categories)
    model.payee = "Blue Tokai"

    model.refreshSuggestions()

    XCTAssertEqual(spy.suggestionLimits, [3])
    XCTAssertEqual(model.visibleSuggestions.count, 3)
  }

  /// A suggestion for a category the picker cannot show is dropped, so no chip
  /// appears with no name.
  func testSuggestionsForUnknownCategoriesAreDropped() {
    let food = category("Food")
    let spy = EntryWriteSpy()
    spy.suggestions = [UUID(), food.id]
    let model = makeModel(spy: spy, categories: [food])
    model.payee = "Blue Tokai"

    model.refreshSuggestions()

    XCTAssertEqual(model.visibleSuggestions.map(\.id), [food.id])
  }

  func testTransfersShowNoSuggestions() {
    let food = category("Food")
    let spy = EntryWriteSpy()
    spy.suggestions = [food.id]
    let model = makeModel(spy: spy, accounts: [account("HDFC"), account("ICICI")], categories: [food])
    model.payee = "Blue Tokai"
    model.kind = .transfer

    model.refreshSuggestions()

    XCTAssertEqual(model.visibleSuggestions, [])
  }

  /// Typing three letters in quick succession asks the store once, after the
  /// pause, not once per keystroke.
  func testTypingIsDebouncedToOneSuggestionQuery() async throws {
    let spy = EntryWriteSpy()
    let model = makeModel(spy: spy, suggestionDelay: .milliseconds(40))

    model.payee = "b"
    model.payee = "bl"
    model.payee = "blu"

    XCTAssertEqual(spy.suggestionLimits, [], "no query before the pause")

    var waited = 0
    while spy.suggestionLimits.isEmpty && waited < 200 {
      try await Task.sleep(for: .milliseconds(10))
      waited += 1
    }
    try await Task.sleep(for: .milliseconds(80))

    XCTAssertEqual(spy.suggestionLimits, [3], "one query for the three keystrokes")
  }
}
