import Foundation
import NomiCore
import SwiftData

/// The real `PipelineStore`. A `@ModelActor`, so the `ModelContext` never
/// leaves its actor and no `@Model` instance crosses a concurrency boundary —
/// only `TransactionSnapshot` values do.
///
/// **This type is driven by `SwiftDataPipelineStoreTests`**, which builds a real
/// container under XCTest. It used to claim no test could reach it, because
/// `swift test` could not construct a `ModelContainer` at all; that was measured
/// wrong (`NomiCore/Support/InMemoryModelContainer.swift` has the numbers).
/// Everything that decides anything still lives above `PipelineStore`, where a
/// test needs no container — keep it that way.
@ModelActor
public actor SwiftDataPipelineStore: PipelineStore {

  /// Every `ModelContext.fetch` this store has made, so a test can assert how
  /// many round trips a call cost (M10). Both shapes of `duplicateGroups`
  /// return the same groups; only the count tells them apart.
  ///
  /// The design asked for a counting `ModelContext`. It is not `open`, so it
  /// cannot be subclassed from here; this is the `RuleEngine.orderingCount`
  /// affordance instead. Actor-isolated, so unlike that one it needs no
  /// `nonisolated(unsafe)` and one store's count never includes another's.
  private(set) var fetchCount = 0

  /// Test seam for `applyTransferMarks`. When set, the save after the legs are
  /// mutated throws this instead of saving, so a test can prove the rollback
  /// (TR4). Nil in production; set only through `failTransferSaves(with:)`.
  private var transferSaveFailure: Error?

  func failTransferSaves(with error: Error?) {
    transferSaveFailure = error
  }

  public func rules() async throws -> [RuleSnapshot] {
    let descriptor = FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.isEnabled })
    return try fetch(descriptor).map(RuleSnapshot.init)
  }

  public func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    let lower = dateRange.lowerBound
    let upper = dateRange.upperBound
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> {
        $0.amountMinor == amountMinor
          && $0.directionRaw == directionRaw
          && $0.date >= lower
          && $0.date <= upper
      }
    )
    return try fetch(descriptor).map(TransactionSnapshot.init)
  }

  /// Two passes, so a reconcile over a clean ledger does not snapshot it.
  ///
  /// The first fetches only `id` and `dedupeKey` and groups them; the second
  /// fetches in full just the rows whose key appeared more than once. On a
  /// ledger with no duplicates, the ordinary case, the second fetch never
  /// happens. SwiftData has no GROUP BY, so the narrow pass still reads every
  /// row — what it no longer does is materialise and snapshot every row (M10).
  ///
  /// Grouped again after the full fetch, not trusted from the first pass:
  /// another context can delete a row between the two, and a group of one is
  /// not a duplicate.
  public func duplicateGroups() async throws -> [[TransactionSnapshot]] {
    var narrow = FetchDescriptor<Transaction>()
    narrow.propertiesToFetch = [\.id, \.dedupeKey]

    var idsByKey: [String: [UUID]] = [:]
    for row in try fetch(narrow) where !row.dedupeKey.isEmpty {
      idsByKey[row.dedupeKey, default: []].append(row.id)
    }

    let duplicatedIDs = idsByKey.values.filter { $0.count > 1 }.flatMap { $0 }
    guard !duplicatedIDs.isEmpty else { return [] }

    let full = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { duplicatedIDs.contains($0.id) }
    )
    var byKey: [String: [TransactionSnapshot]] = [:]
    for row in try fetch(full) {
      byKey[row.dedupeKey, default: []].append(TransactionSnapshot(row))
    }
    return Array(byKey.values.filter { $0.count > 1 })
  }

  public func apply(_ plan: CommitPlan) async throws {
    for snapshot in plan.inserts {
      modelContext.insert(Transaction.make(from: snapshot))
    }

    for snapshot in plan.updates {
      guard let row = try fetchRow(id: snapshot.id) else { continue }
      row.apply(snapshot)
    }

    for id in plan.deletes {
      guard let row = try fetchRow(id: id) else { continue }
      modelContext.delete(row)
    }

    try modelContext.save()
  }

  public func accountFacts() async throws -> [UUID: TransferAccount] {
    let accounts = try fetch(FetchDescriptor<Account>())
    return TransferAccount.byID(accounts.map { ($0.id, TransferAccount(kind: $0.kind, lastFour: $0.lastFour)) })
  }

  /// Both directions by design: the detector needs the opposite leg of a seed
  /// and every competitor of that leg, so the caller reads one amount in one
  /// window. Snapshots come through `init(_:)`, which sets `transferPairAtRead`.
  public func transferCandidates(
    amountMinor: Int,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    let lower = dateRange.lowerBound
    let upper = dateRange.upperBound
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> {
        $0.amountMinor == amountMinor && $0.date >= lower && $0.date <= upper
      }
    )
    return try fetch(descriptor).map(TransactionSnapshot.init)
  }

  /// TR4. Every leg is fetched and judged before the first mutation. Only the
  /// transfer pair and `updatedAt` change, on both legs of each accepted write,
  /// then one save. A failed save rolls the context back and rethrows, so
  /// neither leg of a pair persists alone.
  public func applyTransferMarks(
    _ writes: [TransferPairWrite],
    updatedAt: Date
  ) async throws -> [TransferPairWrite] {
    var rows: [UUID: Transaction] = [:]
    var now: [UUID: TransferLegState] = [:]
    for write in writes {
      for id in [write.first.id, write.second.id] where rows[id] == nil {
        guard let row = try fetchRow(id: id) else { continue }
        rows[id] = row
        now[id] = TransferLegState(id: row.id, accountID: row.accountID, pair: row.transferPair)
      }
    }

    let landed = TransferPairWrite.accepted(writes, now: now)
    guard !landed.isEmpty else { return [] }

    do {
      for write in landed {
        for id in [write.first.id, write.second.id] {
          guard let row = rows[id] else { continue }
          row.transferGroupID = write.pair.groupID
          row.transferSourceRaw = write.pair.sourceRaw
          row.updatedAt = updatedAt
        }
      }
      if let transferSaveFailure { throw transferSaveFailure }
      try modelContext.save()
    } catch {
      modelContext.rollback()
      throw error
    }
    return landed
  }

  private func fetchRow(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try fetch(descriptor).first
  }

  /// The only call site of `modelContext.fetch`, so `fetchCount` cannot miss one.
  private func fetch<Model: PersistentModel>(_ descriptor: FetchDescriptor<Model>) throws -> [Model] {
    fetchCount += 1
    return try modelContext.fetch(descriptor)
  }
}

// MARK: - Snapshot conversion
//
// Confined to this file on purpose: the pure decision code must never mention
// a `@Model` type, or it stops being runnable under `swift test`.

extension RuleSnapshot {
  init(_ rule: Rule) {
    self.init(
      id: rule.id,
      pattern: rule.pattern,
      categoryID: rule.categoryID,
      priority: rule.priority,
      isEnabled: rule.isEnabled,
      scope: rule.scope,
      createdAt: rule.createdAt
    )
  }
}

extension TransactionSnapshot {
  init(_ transaction: Transaction) {
    self.init(
      id: transaction.id,
      date: transaction.date,
      descriptionText: transaction.descriptionText,
      merchantName: transaction.merchantName,
      upiKindRaw: transaction.upiKindRaw,
      counterpartyVPA: transaction.counterpartyVPA,
      normalizedDescription: transaction.normalizedDescription,
      amountMinor: transaction.amountMinor,
      currencyCode: transaction.currencyCode,
      directionRaw: transaction.directionRaw,
      categoryID: transaction.categoryID,
      categorySourceRaw: transaction.categorySourceRaw,
      appliedRuleID: transaction.appliedRuleID,
      accountID: transaction.accountID,
      sourceRaw: transaction.sourceRaw,
      sourceRefs: transaction.sourceRefs,
      mergedCount: transaction.mergedCount,
      needsReview: transaction.needsReview,
      dedupeKey: transaction.dedupeKey,
      createdAt: transaction.createdAt,
      updatedAt: transaction.updatedAt,
      senderDomain: transaction.senderDomain,
      cardFragment: transaction.cardFragment,
      needsReviewReason: transaction.needsReviewReason,
      transferGroupID: transaction.transferGroupID,
      transferSourceRaw: transaction.transferSourceRaw
    )
    // Amendment 3. The only place the pair this snapshot was read with is set.
    self.transferPairAtRead = transaction.transferPair
  }
}

extension Transaction {
  /// A static factory rather than a `convenience init`, to keep this out of
  /// the `@Model` macro's way.
  static func make(from snapshot: TransactionSnapshot) -> Transaction {
    Transaction(
      id: snapshot.id,
      date: snapshot.date,
      descriptionText: snapshot.descriptionText,
      merchantName: snapshot.merchantName,
      upiKindRaw: snapshot.upiKindRaw,
      counterpartyVPA: snapshot.counterpartyVPA,
      normalizedDescription: snapshot.normalizedDescription,
      amountMinor: snapshot.amountMinor,
      currencyCode: snapshot.currencyCode,
      directionRaw: snapshot.directionRaw,
      categoryID: snapshot.categoryID,
      categorySourceRaw: snapshot.categorySourceRaw,
      appliedRuleID: snapshot.appliedRuleID,
      accountID: snapshot.accountID,
      sourceRaw: snapshot.sourceRaw,
      sourceRefs: snapshot.sourceRefs,
      mergedCount: snapshot.mergedCount,
      needsReview: snapshot.needsReview,
      dedupeKey: snapshot.dedupeKey,
      createdAt: snapshot.createdAt,
      updatedAt: snapshot.updatedAt,
      senderDomain: snapshot.senderDomain,
      cardFragment: snapshot.cardFragment,
      needsReviewReasonRaw: snapshot.needsReviewReason?.rawValue,
      transferGroupID: snapshot.transferGroupID,
      transferSourceRaw: snapshot.transferSourceRaw
    )
  }

  /// `id`, `dedupeKey`, `descriptionText`, `normalizedDescription`, `date` and
  /// `createdAt` are written on insert and never rewritten, so they are absent
  /// here on purpose. So are `senderDomain`, `cardFragment` and
  /// `needsReviewReasonRaw` (C4): they record what the *ingester* saw when the
  /// row was created, and a later merge does not change that.
  ///
  /// The transfer pair (DEC-05) is written by compare-and-set (Amendment 3, rule
  /// C): only if the snapshot carries the pair it read from the store, that pair
  /// still equals the row's current pair, and `TransferRules.pipelineMayWrite`
  /// allows the change. Both fields are written together, or neither. A
  /// snapshot not read from the store carries no read pair and never writes the
  /// pair. So a stale snapshot never clears, changes or re-creates a decision,
  /// and never overwrites an unrecognised pair. Residual window, accepted and in
  /// the PR: the read and the current pair both come from this context's copy
  /// of the row, which can predate a save made in another context.
  func apply(_ snapshot: TransactionSnapshot) {
    merchantName = snapshot.merchantName
    upiKindRaw = snapshot.upiKindRaw
    counterpartyVPA = snapshot.counterpartyVPA
    categoryID = snapshot.categoryID
    categorySourceRaw = snapshot.categorySourceRaw
    appliedRuleID = snapshot.appliedRuleID
    accountID = snapshot.accountID
    sourceRefs = snapshot.sourceRefs
    mergedCount = snapshot.mergedCount
    needsReview = snapshot.needsReview
    updatedAt = snapshot.updatedAt
    if TransferRules.pipelineMayWrite(
      read: snapshot.transferPairAtRead,
      current: transferPair,
      incoming: snapshot.transferPair
    ) {
      transferGroupID = snapshot.transferGroupID
      transferSourceRaw = snapshot.transferSourceRaw
    }
  }
}
