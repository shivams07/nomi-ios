import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// `TransactionSnapshot(_ transaction:)` exists in `NomiIngest` but is
/// `internal` — it lives in an extension in `SwiftDataPipelineStore.swift`,
/// which is deliberate on that side (the pure decision code must never mention
/// a `@Model` type) and simply not reachable from here.
///
/// So `NomiApp` gets its own, built on the public memberwise initialiser, in
/// one file for the same reason `NomiIngest` confines its version to one file.
/// The two must agree field for field; the only way they diverge is if
/// `TransactionSnapshot` gains a property, and it is `Equatable`, so a missing
/// field shows up as a value that will not round-trip rather than as silence.
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
      updatedAt: transaction.updatedAt
    )
  }
}

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
