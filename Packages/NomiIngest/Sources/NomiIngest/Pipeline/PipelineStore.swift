import Foundation
import NomiCore

/// The pipeline's persistence seam. `SwiftDataPipelineStore` is the real one;
/// tests supply an in-memory conformer.
///
/// This exists because the SwiftData `@Model` types cannot be constructed under
/// `swift test` on this project's CI at all — the CoreData-backed store traps
/// resolving a bundle name in a headless test binary
/// (`NomiCore/Support/InMemoryModelContainer.swift`). Every dedupe, merge and
/// rule decision therefore lives above this protocol, where it can be executed
/// by a test, and everything below it is compile-verified only. That trade is
/// stated in this unit's PR.
public protocol PipelineStore: Sendable {
  /// Enabled rules. Ordering is the pipeline's business, not the store's.
  func rules() async throws -> [RuleSnapshot]

  /// Rows that could merge with a draft of this amount/direction/date span.
  /// Covers both tiers — an exact match is always inside the near window.
  func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot]

  /// Every row whose `categorySource` is not `.manual` — the retroactive rule
  /// pass's working set.
  func rulePassCandidates() async throws -> [TransactionSnapshot]

  /// Every row whose `appliedRuleID` is this rule.
  func rows(appliedRuleID: UUID) async throws -> [TransactionSnapshot]

  /// Rows grouped by `dedupeKey`, only groups of two or more. The R5
  /// reconcile pass's input.
  func duplicateGroups() async throws -> [[TransactionSnapshot]]

  /// Insert, update and delete in one transaction.
  func apply(_ plan: CommitPlan) async throws
}
