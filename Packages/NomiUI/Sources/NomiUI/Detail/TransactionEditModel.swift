import Foundation
import NomiCore
import Observation

/// The edit sheet's state and its Save, outside the view (S3b), so plain XCTest can
/// drive them against a spy editor. The detail screen creates one on Edit and
/// presents the sheet from it.
///
/// Save writes only what changed: the facts (`update`) first, then the direction
/// (`setDirection`). A transfer leg is never sent a direction. A write that lands
/// moves the saved baseline on, so a retry after a refused write repeats only the
/// write that failed.
@Observable @MainActor final class TransactionEditModel: Identifiable {
  /// The row as the store last held it, for the change check and the delete copy.
  private struct Saved: Equatable {
    var amountMinor: Int
    var date: Date
    var descriptionText: String
    var note: String?
    var direction: Direction
  }

  /// The sheet's identity for `.sheet(item:)`; the row's id, `Sendable`, so it is readable off the main actor.
  nonisolated let id: UUID
  let transactionID: UUID
  let isTransfer: Bool
  let currencyCode: String
  /// The name the delete alert uses: the merchant, or the bank text when there is none.
  let merchantLabel: String
  @ObservationIgnored private let editor: TransactionEditing
  @ObservationIgnored private let calendar: Calendar
  @ObservationIgnored private var saved: Saved

  var amountText: String
  var date: Date
  var descriptionText: String
  var noteText: String
  var direction: Direction
  var errorMessage: String?

  init(
    transactionID: UUID, amountMinor: Int, date: Date, descriptionText: String, note: String?,
    direction: Direction, isTransfer: Bool, currencyCode: String, merchantLabel: String,
    editor: TransactionEditing, calendar: Calendar = .current
  ) {
    self.transactionID = transactionID
    self.id = transactionID
    self.isTransfer = isTransfer
    self.currencyCode = currencyCode
    self.merchantLabel = merchantLabel
    self.editor = editor
    self.calendar = calendar
    self.date = date
    self.descriptionText = descriptionText
    self.noteText = note ?? ""
    self.direction = direction
    amountText = String(format: "%.2f", Double(amountMinor) / 100)
    saved = Saved(amountMinor: amountMinor, date: date, descriptionText: descriptionText, note: note, direction: direction)
  }

  // MARK: - Fields

  /// A transfer leg cannot change direction: the control is off until it is unmarked.
  var isDirectionEditable: Bool { !isTransfer }

  var directionCaption: String? {
    isTransfer ? String(localized: "Unmark the transfer to change this", bundle: .module) : nil
  }

  var amountMinor: Int { EntryAmount.minorUnits(from: amountText) }

  /// What Save sends as the note: blank input is no note (`TransactionDetailLogic.noteToSave`).
  var noteToSave: String? { TransactionDetailLogic.noteToSave(from: noteText) }

  /// Keeps the amount field to what `EntryAmount` accepts, as the keypad types it.
  func amountDidChange(_ newValue: String) {
    let sanitized = EntryAmount.sanitizeInput(newValue)
    if sanitized != newValue { amountText = sanitized }
  }

  // MARK: - Save

  private var directionChanged: Bool { isDirectionEditable && direction != saved.direction }

  /// Whether anything the sheet can change differs from the row as stored.
  var hasChanges: Bool {
    amountMinor != saved.amountMinor || date != saved.date || descriptionText != saved.descriptionText
      || noteToSave != saved.note || directionChanged
  }

  /// Save is enabled only when the amount is valid and something changed (the DT rule).
  var canSave: Bool {
    EntrySaveGate.isEnabled(amountMinor: amountMinor) && hasChanges
  }

  /// Writes the changes. Returns true when the sheet should dismiss. A refused
  /// write leaves the sheet open with the error, and the writes that landed stay
  /// landed.
  func save() -> Bool {
    do {
      let amount = amountMinor
      let note = noteToSave
      if amount != saved.amountMinor || date != saved.date || descriptionText != saved.descriptionText
        || note != saved.note
      {
        try editor.update(transactionID, amountMinor: amount, date: date, descriptionText: descriptionText, note: note)
        saved.amountMinor = amount
        saved.date = date
        saved.descriptionText = descriptionText
        saved.note = note
      }
      if directionChanged {
        try editor.setDirection(transactionID, to: direction)
        saved.direction = direction
      }
      errorMessage = nil
      return true
    } catch {
      errorMessage = "Could not save the changes."
      return false
    }
  }

  // MARK: - Delete

  /// The alert body for Delete, from the row as stored: what the delete takes out of
  /// every total, plus the transfer sentence when this row is a leg.
  var deleteMessage: String {
    TransactionDetailLogic.deleteConfirmationSentence(
      amountText: NomiFormatters.amountString(minor: saved.amountMinor, currencyCode: currencyCode),
      merchant: merchantLabel, date: saved.date, calendar: calendar, isTransfer: isTransfer)
  }

  /// Runs the delete through `perform`, the store's delete in the view. Returns true
  /// when the row is gone and the sheet and its detail should close.
  func delete(_ perform: (UUID) throws -> Void) -> Bool {
    do {
      try perform(transactionID)
      return true
    } catch {
      errorMessage = "Could not delete this transaction."
      return false
    }
  }
}
