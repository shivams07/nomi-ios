import Foundation
import NomiCore
import SwiftData

/// The real `PipelineStore`. A `@ModelActor`, so the `ModelContext` never
/// leaves its actor and no `@Model` instance crosses a concurrency boundary —
/// only `TransactionSnapshot` values do.
///
/// **This type is compile-verified only.** `swift test` cannot construct a
/// `ModelContainer` in this CI (`NomiCore/Support/InMemoryModelContainer.swift`
/// explains why), so nothing below this line is executed by any test on this
/// project. Everything that decides anything lives above `PipelineStore` and is
/// covered there. Keep it that way: logic added here is logic nobody can test.
@ModelActor
public actor SwiftDataPipelineStore: PipelineStore {

  public func rules() async throws -> [RuleSnapshot] {
    let descriptor = FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.isEnabled })
    return try modelContext.fetch(descriptor).map(RuleSnapshot.init)
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
    return try modelContext.fetch(descriptor).map(TransactionSnapshot.init)
  }

  public func rulePassCandidates() async throws -> [TransactionSnapshot] {
    let manual = CategorySource.manual.rawValue
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.categorySourceRaw != manual }
    )
    return try modelContext.fetch(descriptor).map(TransactionSnapshot.init)
  }

  public func rows(appliedRuleID: UUID) async throws -> [TransactionSnapshot] {
    let target: UUID? = appliedRuleID
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.appliedRuleID == target }
    )
    return try modelContext.fetch(descriptor).map(TransactionSnapshot.init)
  }

  public func duplicateGroups() async throws -> [[TransactionSnapshot]] {
    // A full scan, deliberately. This runs on launch and on remote-change
    // notifications, not per row, and SwiftData has no GROUP BY to lean on.
    let all = try modelContext.fetch(FetchDescriptor<Transaction>())
    var byKey: [String: [TransactionSnapshot]] = [:]
    for row in all where !row.dedupeKey.isEmpty {
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

  private func fetchRow(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
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
      needsReviewReason: transaction.needsReviewReason
    )
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
      needsReviewReasonRaw: snapshot.needsReviewReason?.rawValue
    )
  }

  /// `id`, `dedupeKey`, `descriptionText`, `normalizedDescription`, `date` and
  /// `createdAt` are written on insert and never rewritten, so they are absent
  /// here on purpose. So are `senderDomain`, `cardFragment` and
  /// `needsReviewReasonRaw` (C4): they record what the *ingester* saw when the
  /// row was created, and a later merge does not change that.
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
  }
}
