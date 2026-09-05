import Foundation
import NomiCore

/// Mutates the `Transaction` in place, same as `FakeTransactionStore.setCategory`
/// — `transactions` defaults to `PreviewData.transactions`, the same instances
/// a `LedgerPreviewSupport`-seeded container holds, so an edit here is visible
/// through `@Query` without a second write path.
@MainActor
public final class FakeTransactionEditor: TransactionEditing {
  public var transactions: [Transaction]

  public init(transactions: [Transaction] = PreviewData.transactions) {
    self.transactions = transactions
  }

  public func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    let normalized = normalizeDescription(descriptionText)
    transaction.amountMinor = amountMinor
    transaction.date = date
    transaction.descriptionText = descriptionText
    transaction.normalizedDescription = normalized
    transaction.dedupeKey = makeDedupeKey(
      date: date,
      amountMinor: amountMinor,
      directionRaw: transaction.directionRaw,
      normalizedDescription: normalized
    )
    transaction.updatedAt = Date()
  }
}
