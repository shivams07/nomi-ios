import CryptoKit
import Foundation
import NomiCore

/// Mutates the `Transaction` in place, same as `FakeTransactionStore.setCategory`
/// — `transactions` defaults to `PreviewData.transactions`, the same instances
/// a `LedgerPreviewSupport`-seeded container holds, so an edit here is visible
/// through `@Query` without a second write path.
@MainActor
public final class FakeTransactionEditor: TransactionEditing {
  public var transactions: [Transaction]
  /// The device calendar, as `SwiftDataTransactionEditor` (DEC-05 R6).
  private let calendar: Calendar

  public init(
    transactions: [Transaction] = PreviewData.transactions,
    calendar: Calendar = .current
  ) {
    self.transactions = transactions
    self.calendar = calendar
  }

  /// Mirrors `SwiftDataTransactionEditor.setTransfer`, rule for rule, over the
  /// in-memory rows, so a preview cannot disagree with the app about a mark.
  public func setTransfer(_ id: UUID, isTransfer: Bool) throws {
    guard let row = transactions.first(where: { $0.id == id }) else { return }
    let timestamp = Date()

    if isTransfer {
      guard row.transferGroupID == nil else { return }
      if let partner = manualPartner(for: row) {
        let group = TransferGroupID.make(row.id, partner.id)
        row.transferGroupID = group
        row.transferSource = .manual
        partner.transferGroupID = group
        partner.transferSource = .manual
        partner.updatedAt = timestamp
      } else {
        row.transferGroupID = TransferGroupID.make(single: row.id)
        row.transferSource = .manual
      }
    } else {
      guard row.transferGroupID != nil || row.transferSource != .rejected else { return }
      if let group = row.transferGroupID {
        for member in transactions where member.transferGroupID == group && member.id != row.id {
          member.transferGroupID = nil
          member.transferSource = nil
          member.updatedAt = timestamp
        }
      }
      row.transferGroupID = nil
      row.transferSource = .rejected
    }

    row.updatedAt = timestamp
  }

  /// I-11 Amendment 1, as `SwiftDataTransactionEditor.editedDedupeKey`: a manual row keeps the natural
  /// key, and any other source is salted with its id.
  private func editedDedupeKey(for row: Transaction) -> String {
    let natural = makeDedupeKey(
      date: row.date,
      amountMinor: row.amountMinor,
      directionRaw: row.directionRaw,
      normalizedDescription: row.normalizedDescription
    )
    guard row.sourceRaw != IngestSource.manual.rawValue else { return natural }
    let salted = natural + "|edited|" + row.id.uuidString.lowercased()
    return SHA256.hash(data: Data(salted.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  private func manualPartner(for row: Transaction) -> Transaction? {
    guard row.currencyCode == "INR", row.accountID != nil else { return nil }
    let candidates = transactions.filter { $0.id != row.id && $0.amountMinor == row.amountMinor }
    guard
      let partnerID = TransferRules.manualPartner(
        for: row.transferLeg,
        among: candidates.map(\.transferLeg),
        calendar: calendar
      )
    else { return nil }
    return candidates.first { $0.id == partnerID }
  }

  /// Mirrors `SwiftDataTransactionEditor.setDirection` over the in-memory row.
  public func setDirection(_ id: UUID, to direction: Direction) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    guard !transaction.isTransfer else { throw TransactionEditError.transferLeg }
    transaction.directionRaw = direction.rawValue
    transaction.dedupeKey = editedDedupeKey(for: transaction)
    transaction.updatedAt = Date()
  }

  public func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String, note: String?) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    let normalized = normalizeDescription(descriptionText)
    transaction.amountMinor = amountMinor
    transaction.date = date
    transaction.descriptionText = descriptionText
    transaction.normalizedDescription = normalized
    transaction.dedupeKey = editedDedupeKey(for: transaction)
    transaction.note = note
    transaction.updatedAt = Date()
  }
}
