import Foundation
import NomiCore

/// What every write in the app does *after* it writes: drop the aggregate
/// cache, and tell the post-commit observer which categories moved.
///
/// It exists so the stores below stay dumb. Each of them knows how to change
/// one kind of row and nothing about budgets, notifications or caching; the
/// composition root decides what a write means.
///
/// `affectedCategoryIDs` is the same payload `IngestPipeline` puts on its own
/// hook, and it is passed for the same reason: the observer filters by it, so a
/// write that moved nothing between categories must send an empty set rather
/// than a plausible-looking one.
@MainActor
public final class WriteCoordinator {
  private let cache: InsightsCache
  private var observer: (any PostCommitObserver)?

  public init(cache: InsightsCache) {
    self.cache = cache
  }

  public func setObserver(_ observer: (any PostCommitObserver)?) {
    self.observer = observer
  }

  /// The cache is dropped synchronously — a view re-rendering on the next
  /// runloop tick must not be able to read a stale total. The observer is
  /// async and is dispatched, not awaited: budget evaluation must not sit in
  /// front of the UI updating after the user taps Save.
  public func didWrite(affectedCategoryIDs: Set<UUID> = []) {
    cache.invalidate()
    guard !affectedCategoryIDs.isEmpty, let observer else { return }
    Task { await observer.didCommit(affectedCategoryIDs: affectedCategoryIDs) }
  }
}

/// Bridges `IngestPipeline`'s commit hook to both things that care about a
/// commit: the aggregate cache, and the budget alerts.
///
/// The pipeline writes through `SwiftDataPipelineStore`, a `@ModelActor` with
/// its **own** `ModelContext`. Nothing about that context's save reaches this
/// one's cached `PeriodInsights` values — they are plain structs held in a
/// dictionary, not live objects — so without this relay the dashboard would
/// keep showing pre-sync totals until the next unrelated write.
///
/// Order is cache first, budgets second, and it matters: `BudgetAlertObserver`
/// reads progress back through `InsightsStore`, and reading it before the
/// invalidation would evaluate the alert against the totals from before the
/// commit that triggered it.
public final class PipelineCommitRelay: PostCommitObserver, @unchecked Sendable {
  private let coordinator: WriteCoordinator
  private let downstream: any PostCommitObserver

  public init(coordinator: WriteCoordinator, downstream: any PostCommitObserver) {
    self.coordinator = coordinator
    self.downstream = downstream
  }

  public func didCommit(affectedCategoryIDs: Set<UUID>) async {
    await MainActor.run {
      coordinator.invalidateOnly()
    }
    await downstream.didCommit(affectedCategoryIDs: affectedCategoryIDs)
  }
}

extension WriteCoordinator {
  /// Invalidation without the observer hop — for callers that are already
  /// downstream of the observer and would otherwise re-enter it.
  func invalidateOnly() {
    cache.invalidate()
  }
}
