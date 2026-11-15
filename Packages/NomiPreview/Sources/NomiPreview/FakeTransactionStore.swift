import Foundation
import NomiCore

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
      ),
      note: Self.storedNote(draft.note)
    )
    transactions.append(transaction)
    lastUsedCategory = draft.categoryID
    return transaction
  }

  /// Mirrors `SwiftDataTransactionStore.addTransfer` rule for rule, over the in-memory rows.
  public func addTransfer(
    amountMinor: Int,
    date: Date,
    fromAccountID: UUID,
    toAccountID: UUID,
    note: String?
  ) throws -> (Transaction, Transaction) {
    guard AmountRules.isValidTransactionAmount(amountMinor) else {
      throw AmountValidationError.outOfRange(amountMinor: amountMinor)
    }
    guard fromAccountID != toAccountID else { throw TransactionStoreError.sameAccount }

    let group = UUID()
    let stored = Self.storedNote(note)
    let descriptionText = "Transfer"
    let normalized = normalizeDescription(descriptionText)
    func leg(_ direction: Direction, accountID: UUID) -> Transaction {
      Transaction(
        date: date,
        descriptionText: descriptionText,
        normalizedDescription: normalized,
        amountMinor: amountMinor,
        directionRaw: direction.rawValue,
        accountID: accountID,
        sourceRaw: IngestSource.manual.rawValue,
        sourceRefs: [SourceRef(source: .manual, externalID: UUID().uuidString, capturedAt: Date())],
        dedupeKey: makeDedupeKey(
          date: date,
          amountMinor: amountMinor,
          directionRaw: direction.rawValue,
          normalizedDescription: normalized
        ),
        note: stored,
        transferGroupID: group,
        transferSourceRaw: TransferSource.manual.rawValue
      )
    }
    let debit = leg(.debit, accountID: fromAccountID)
    let credit = leg(.credit, accountID: toAccountID)
    transactions.append(contentsOf: [debit, credit])
    return (debit, credit)
  }

  /// The account of the most recently created manual row that has one, or nil.
  public func lastUsedAccountID() -> UUID? {
    transactions
      .filter { $0.sourceRaw == IngestSource.manual.rawValue && $0.accountID != nil }
      .max { $0.createdAt < $1.createdAt }?
      .accountID
  }

  /// Mirrors `SwiftDataTransactionStore.suggestedCategories`, except the category check. This fake
  /// holds no categories, so it cannot drop a category that was deleted; the real store does.
  public func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID] {
    let needle = normalizeDescription(text)
    guard needle.count >= 2, limit > 0 else { return [] }

    var count: [UUID: Int] = [:]
    var newest: [UUID: Date] = [:]
    for row in transactions where row.normalizedDescription.contains(needle) && row.transferGroupID == nil {
      guard let category = row.categoryID else { continue }
      count[category, default: 0] += 1
      newest[category] = max(newest[category] ?? .distantPast, row.date)
    }
    let ordered = count.keys.sorted { lhs, rhs in
      if count[lhs] != count[rhs] { return (count[lhs] ?? 0) > (count[rhs] ?? 0) }
      if newest[lhs] != newest[rhs] { return (newest[lhs] ?? .distantPast) > (newest[rhs] ?? .distantPast) }
      return lhs.uuidString < rhs.uuidString
    }
    return Array(ordered.prefix(limit))
  }

  /// I-11. Trimmed, and nil when nothing is left: the same rule the real store applies.
  private static func storedNote(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
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
