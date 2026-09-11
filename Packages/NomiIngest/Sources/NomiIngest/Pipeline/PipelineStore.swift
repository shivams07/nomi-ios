import Foundation
import NomiCore

/// The pipeline's persistence seam. `SwiftDataPipelineStore` is the real one;
/// tests supply an in-memory conformer.
///
/// This exists so every dedupe, merge and rule decision lives above the
/// protocol, over values, where a test needs no container to run it. The reason
/// first given — that `@Model` types could not be constructed under `swift
/// test` at all — was measured wrong: the trap is swift-testing's, and XCTest
/// builds a container fine (`NomiCore/Support/InMemoryModelContainer.swift`).
/// `SwiftDataPipelineStoreTests` is the worked example below this line.
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

  /// Rows grouped by `dedupeKey`, only groups of two or more. The R5
  /// reconcile pass's input.
  func duplicateGroups() async throws -> [[TransactionSnapshot]]

  /// Insert, update and delete in one transaction.
  func apply(_ plan: CommitPlan) async throws
}
