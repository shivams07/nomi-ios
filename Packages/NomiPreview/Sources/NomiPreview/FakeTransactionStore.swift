import Foundation
import NomiCore
import SwiftData

@MainActor
public final class FakeTransactionStore: TransactionStore {
  public var transactions: [Transaction]
  private var lastUsedCategory: UUID?

  public init(transactions: [Transaction] = PreviewData.transactions) {
    self.transactions = transactions
  }

  public func add(_ draft: ManualTransactionDraft) throws -> Transaction {
    let normalized = normalizeDescription(draft.descriptionText)
    let transaction = Transaction(
      date: draft.date,
      descriptionText: draft.descriptionText,
      normalizedDescription: normalized,
      amountMinor: draft.amountMinor,
      directionRaw: draft.direction.rawValue,
      categoryID: draft.categoryID,
      categorySourceRaw: draft.categoryID == nil ? CategorySource.none.rawValue : CategorySource.manual.rawValue,
      accountID: draft.accountID,
      sourceRaw: IngestSource.manual.rawValue,
      dedupeKey: makeDedupeKey(
        date: draft.date,
        amountMinor: draft.amountMinor,
        directionRaw: draft.direction.rawValue,
        normalizedDescription: normalized
      )
    )
    InMemoryModelContainer.inserted(transaction)
    transactions.append(transaction)
    lastUsedCategory = draft.categoryID
    return transaction
  }

  public func setCategory(_ id: UUID, to categoryID: UUID?) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    transaction.categoryID = categoryID
    transaction.categorySourceRaw = CategorySource.manual.rawValue
    transaction.updatedAt = Date()
    lastUsedCategory = categoryID
  }

  public func setAccount(_ id: UUID, to accountID: UUID?) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    transaction.accountID = accountID
    transaction.updatedAt = Date()
  }

  public func delete(_ id: UUID) throws {
    transactions.removeAll { $0.id == id }
  }

  public func reviewQueue() throws -> [Transaction] {
    transactions.filter { $0.mergedCount > 1 || $0.needsReview || $0.accountID == nil }
  }

  public func dismissReview(_ id: UUID) throws {
    guard let transaction = transactions.first(where: { $0.id == id }) else { return }
    transaction.needsReview = false
  }

  public func lastUsedCategoryID() -> UUID? {
    lastUsedCategory
  }
}
