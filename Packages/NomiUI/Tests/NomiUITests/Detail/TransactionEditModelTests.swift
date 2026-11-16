import Foundation
import NomiCore
import XCTest
@testable import NomiUI

/// The edit sheet's model (S3b). The editor is a spy that records each write in
/// order and can refuse one, so the save rules are checked against the calls made.
@MainActor
final class TransactionEditModelTests: XCTestCase {

  private enum Call: Equatable {
    case update(UUID, Int, Date, String, String?)
    case setDirection(UUID, Direction)
    case setTransfer(UUID, Bool)
  }

  private enum SpyError: Error { case refused }

  @MainActor
  private final class SpyEditor: TransactionEditing {
    private(set) var calls: [Call] = []
    var updateError: Error?
    var directionError: Error?

    func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String, note: String?) throws {
      calls.append(.update(id, amountMinor, date, descriptionText, note))
      if let updateError { throw updateError }
    }

    func setTransfer(_ id: UUID, isTransfer: Bool) throws {
      calls.append(.setTransfer(id, isTransfer))
    }

    func setDirection(_ id: UUID, to direction: Direction) throws {
      calls.append(.setDirection(id, direction))
      if let directionError { throw directionError }
    }
  }

  private let rowID = UUID()
  private let day = Date(timeIntervalSince1970: 1_731_500_000)

  /// What the amount field does on each keystroke: the typed text is stored, then sanitised.
  private func type(_ model: TransactionEditModel, _ text: String) {
    model.amountText = text
    model.amountDidChange(text)
  }

  private func makeModel(
    editor: SpyEditor, isTransfer: Bool = false, note: String? = nil, direction: Direction = .debit
  ) -> TransactionEditModel {
    TransactionEditModel(
      transactionID: rowID, amountMinor: 84_500, date: day, descriptionText: "UPI OLACABS",
      note: note, direction: direction, isTransfer: isTransfer, currencyCode: "INR",
      merchantLabel: "Ola", editor: editor, calendar: Calendar(identifier: .gregorian))
  }

  // MARK: - What Save writes

  func testUnchangedSaveWritesNothingAndDismisses() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    XCTAssertFalse(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [])
    XCTAssertNil(model.errorMessage)
  }

  func testAmountOnlyCallsUpdateOnly() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    type(model, "900.00")
    XCTAssertTrue(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 90_000, day, "UPI OLACABS", nil)])
  }

  func testDirectionOnlyCallsSetDirectionOnly() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    model.direction = .credit
    XCTAssertTrue(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.setDirection(rowID, .credit)])
  }

  func testAmountAndDirectionCallUpdateThenSetDirection() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    type(model, "900.00")
    model.direction = .credit
    XCTAssertTrue(model.save())
    XCTAssertEqual(
      editor.calls,
      [.update(rowID, 90_000, day, "UPI OLACABS", nil), .setDirection(rowID, .credit)])
  }

  func testNoteOnlyCallsUpdateWithTheTrimmedNote() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    model.noteText = "  Split with Riya "
    XCTAssertTrue(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 84_500, day, "UPI OLACABS", "Split with Riya")])
  }

  func testBlankNoteIsSavedAsNoNote() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor, note: "Old")
    model.noteText = "   "
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 84_500, day, "UPI OLACABS", nil)])
  }

  func testDescriptionOnlyCallsUpdateWithTheNewDescription() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    model.descriptionText = "OLA RIDE"
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 84_500, day, "OLA RIDE", nil)])
  }

  func testDateOnlyCallsUpdateWithTheNewDate() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor)
    let later = day.addingTimeInterval(86_400)
    model.date = later
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 84_500, later, "UPI OLACABS", nil)])
  }

  // MARK: - Transfer legs

  /// A transfer leg cannot change direction: the control is off, and a direction
  /// set anyway is never written.
  func testTransferLegNeverCallsSetDirection() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor, isTransfer: true)
    XCTAssertFalse(model.isDirectionEditable)
    XCTAssertEqual(model.directionCaption, "Unmark the transfer to change this")
    model.direction = .credit
    XCTAssertFalse(model.canSave)
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [])
  }

  func testTransferLegStillSavesItsAmountWithoutADirectionWrite() {
    let editor = SpyEditor()
    let model = makeModel(editor: editor, isTransfer: true)
    type(model, "500.00")
    model.direction = .credit
    XCTAssertTrue(model.save())
    XCTAssertEqual(editor.calls, [.update(rowID, 50_000, day, "UPI OLACABS", nil)])
  }

  func testOrdinaryRowShowsNoTransferCaption() {
    let model = makeModel(editor: SpyEditor())
    XCTAssertTrue(model.isDirectionEditable)
    XCTAssertNil(model.directionCaption)
  }

  // MARK: - Failures keep the sheet

  func testRefusedUpdateShowsTheErrorAndKeepsTheSheet() {
    let editor = SpyEditor()
    editor.updateError = SpyError.refused
    let model = makeModel(editor: editor)
    type(model, "900.00")
    XCTAssertFalse(model.save())
    XCTAssertEqual(model.errorMessage, "Could not save the changes.")
    XCTAssertEqual(editor.calls, [.update(rowID, 90_000, day, "UPI OLACABS", nil)])
  }

  /// The update lands and the direction is refused. Retrying writes only the
  /// step that failed, so the amount is not written twice.
  func testRefusedDirectionAfterAnUpdateRetriesOnlyTheDirection() {
    let editor = SpyEditor()
    editor.directionError = SpyError.refused
    let model = makeModel(editor: editor)
    type(model, "900.00")
    model.direction = .credit
    XCTAssertFalse(model.save())
    XCTAssertEqual(model.errorMessage, "Could not save the changes.")

    editor.directionError = nil
    XCTAssertTrue(model.save())
    XCTAssertNil(model.errorMessage)
    XCTAssertEqual(
      editor.calls,
      [
        .update(rowID, 90_000, day, "UPI OLACABS", nil),
        .setDirection(rowID, .credit),
        .setDirection(rowID, .credit),
      ])
  }

  // MARK: - Save gate

  func testZeroAmountCannotSave() {
    let model = makeModel(editor: SpyEditor())
    type(model, "0")
    model.descriptionText = "Changed"
    XCTAssertFalse(model.canSave)
  }

  func testEmptyAmountCannotSave() {
    let model = makeModel(editor: SpyEditor())
    type(model, "")
    XCTAssertFalse(model.canSave)
  }

  /// Letters are dropped and a second decimal separator is dropped, as the amount field types them.
  func testAmountInputIsKeptToWhatEntryAccepts() {
    let model = makeModel(editor: SpyEditor())
    type(model, "a1b2.3c4.5")
    XCTAssertEqual(model.amountText, "12.345")
    // Three decimal places are not an amount (R8): the gate stays shut.
    XCTAssertEqual(model.amountMinor, 0)
    XCTAssertFalse(model.canSave)
  }

  // MARK: - Delete

  func testDeleteMessageNamesTheRowAndAddsTheTransferSentenceOnlyForALeg() {
    let ordinary = makeModel(editor: SpyEditor())
    let leg = makeModel(editor: SpyEditor(), isTransfer: true)
    XCTAssertTrue(ordinary.deleteMessage.hasSuffix("will be removed from every total."))
    XCTAssertFalse(ordinary.deleteMessage.contains("matching transfer"))
    XCTAssertTrue(
      leg.deleteMessage.hasSuffix(
        "will be removed from every total. Its matching transfer will count as an ordinary transaction."))
    XCTAssertTrue(ordinary.deleteMessage.contains("Ola"))
  }

  func testDeleteRunsTheStoreAndReportsSuccess() {
    let model = makeModel(editor: SpyEditor())
    var deleted: [UUID] = []
    XCTAssertTrue(model.delete { deleted.append($0) })
    XCTAssertEqual(deleted, [rowID])
    XCTAssertNil(model.errorMessage)
  }

  func testRefusedDeleteShowsTheErrorAndReportsFailure() {
    let model = makeModel(editor: SpyEditor())
    XCTAssertFalse(model.delete { _ in throw SpyError.refused })
    XCTAssertEqual(model.errorMessage, "Could not delete this transaction.")
  }
}
