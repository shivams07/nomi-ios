import Foundation
import NomiCore

/// Field resolution when a draft merges into an existing row, and when the
/// reconcile pass collapses two rows that CloudKit delivered separately (R5).
/// Pure.
enum MergeResolution {

  private static func rank(_ source: CategorySource) -> Int {
    switch source {
    case .none: return 0
    case .rule: return 1
    case .manual: return 2
    }
  }

  /// Folds `derived` into `existing`. Returns `nil` when nothing changed —
  /// which is the ordinary outcome of re-ingesting a contributor already
  /// recorded on the row, and is what makes re-importing the same CSV a true
  /// no-op rather than an ever-growing `mergedCount`.
  ///
  /// `descriptionText`, `normalizedDescription`, `dedupeKey` and `date` are
  /// the surviving row's, always. The incoming draft never rewrites them.
  static func merging(
    _ derived: DerivedDraft,
    into existing: TransactionSnapshot,
    tier: MergeTier,
    now: Date
  ) -> TransactionSnapshot? {
    let draft = derived.draft
    var merged = existing

    let ref = draft.sourceRef
    if !existing.hasSourceRef(ref) {
      merged.sourceRefs.append(ref)
      merged.mergedCount += 1
    }

    if rank(draft.categorySource) > rank(existing.categorySource) {
      merged.categoryID = draft.categoryID
      merged.categorySourceRaw = draft.categorySource.rawValue
      merged.appliedRuleID = nil
    }

    if let incomingAccount = draft.accountID {
      if merged.accountID == nil {
        merged.accountID = incomingAccount
      } else if merged.accountID != incomingAccount {
        // Two sources disagree about which account this is. Keep the earlier
        // one and let a human decide (§1.2).
        merged.needsReview = true
      }
    }

    merged.needsReview = merged.needsReview || draft.needsReview || tier == .near

    // Display-only, re-derivable, feeds nothing (§2.4). Fill a gap, never
    // overwrite.
    merged.merchantName = merged.merchantName ?? derived.merchantName
    merged.upiKindRaw = merged.upiKindRaw ?? derived.upiKindRaw
    merged.counterpartyVPA = merged.counterpartyVPA ?? derived.counterpartyVPA

    guard merged != existing else { return nil }
    merged.updatedAt = now
    return merged
  }

  /// Collapses a group of rows sharing a `dedupeKey` into the earliest one.
  /// Returns the survivor and the ids to delete.
  static func collapsing(
    _ group: [TransactionSnapshot],
    now: Date
  ) -> (survivor: TransactionSnapshot, removed: [UUID])? {
    guard group.count > 1 else { return nil }

    let ordered = group.sorted { lhs, rhs in
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }

    var survivor = ordered[0]
    let others = Array(ordered.dropFirst())

    for row in others {
      for ref in row.sourceRefs where !survivor.hasSourceRef(ref) {
        survivor.sourceRefs.append(ref)
      }

      if rank(row.categorySource) > rank(survivor.categorySource) {
        survivor.categoryID = row.categoryID
        survivor.categorySourceRaw = row.categorySourceRaw
        survivor.appliedRuleID = row.appliedRuleID
      }

      if let account = row.accountID {
        if survivor.accountID == nil {
          survivor.accountID = account
        } else if survivor.accountID != account {
          survivor.needsReview = true
        }
      }

      survivor.needsReview = survivor.needsReview || row.needsReview
      survivor.merchantName = survivor.merchantName ?? row.merchantName
      survivor.upiKindRaw = survivor.upiKindRaw ?? row.upiKindRaw
      survivor.counterpartyVPA = survivor.counterpartyVPA ?? row.counterpartyVPA
    }

    survivor.mergedCount = ordered.reduce(0) { $0 + max(1, $1.mergedCount) }
    survivor.updatedAt = now

    return (survivor, others.map(\.id))
  }
}
