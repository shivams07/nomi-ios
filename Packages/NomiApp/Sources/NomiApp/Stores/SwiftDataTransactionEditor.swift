import Foundation
import NomiCore
import SwiftData

/// The real `TransactionEditing`. Constructed directly in `RootView` from
/// `environment.container.mainContext` and `environment.coordinator` rather
/// than living on `AppEnvironment` — that file belongs to
/// `park/account-binding-loop`. Fold both this construction and the protocol
/// into `AppEnvironment`/`TransactionStore` once units 1, 3 and 5a have all
/// merged (see `TransactionEditing`'s note).
@MainActor
public final class SwiftDataTransactionEditor: TransactionEditing {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let now: () -> Date

  public init(
    context: ModelContext,
    coordinator: WriteCoordinator,
    now: @escaping () -> Date = { Date() }
  ) {
    self.context = context
    self.coordinator = coordinator
    self.now = now
  }

  public func update(_ id: UUID, amountMinor: Int, date: Date, descriptionText: String) throws {
    guard let row = try row(id: id) else { return }
    let normalized = normalizeDescription(descriptionText)

    row.amountMinor = amountMinor
    row.date = date
    row.descriptionText = descriptionText
    row.normalizedDescription = normalized
    // No `calendar:` argument — this editor inherits whichever default
    // `makeDedupeKey` has when `park/dedupe-key-ist` merges, same as every
    // other call site the fix plan didn't touch.
    row.dedupeKey = makeDedupeKey(
      date: date,
      amountMinor: amountMinor,
      directionRaw: row.directionRaw,
      normalizedDescription: normalized
    )
    row.updatedAt = now()

    try context.save()
    coordinator.didWrite(affectedCategoryIDs: Set([row.categoryID].compactMap { $0 }))
  }

  private func row(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
