import Foundation

/// Everything the evaluator needs, read at one instant.
public struct BudgetAlertContext: Sendable, Equatable {
  public let progress: [BudgetProgress]
  public let firedKeys: Set<String>
  public let settings: NotificationSettings

  public init(progress: [BudgetProgress], firedKeys: Set<String>, settings: NotificationSettings) {
    self.progress = progress
    self.firedKeys = firedKeys
    self.settings = settings
  }
}

/// U10 owns no store. This is the seam U8 implements: it reads
/// `InsightsStore.budgetProgress`, turns stored `BudgetAlertLog` rows into
/// `firedKeys` via `BudgetAlertEvaluator.logKey`, and persists the rows for the
/// alerts handed back.
public protocol BudgetAlertContextProviding: AnyObject, Sendable {
  func currentContext() async -> BudgetAlertContext
  /// Persist one `BudgetAlertLog` row per alert, carrying its `wasSuppressed`.
  /// Called *before* anything is presented — see `BudgetAlertObserver`.
  func recordFired(_ alerts: [BudgetAlert]) async
}

/// Joins the evaluator to the scheduler on U4's commit hook. U4 must not know
/// budgets exist; U8 registers this.
///
/// Ordering is deliberate: the log rows are written **before** the notification
/// is scheduled. Backwards, a scheduling failure would leave no row and the
/// alert would fire again on the next commit — and "exactly one notification per
/// category per month" is the acceptance criterion, whereas a notification lost
/// to a scheduler error is a soft failure.
public final class BudgetAlertObserver: PostCommitObserver {
  private let context: any BudgetAlertContextProviding
  private let scheduler: any BudgetNotificationScheduling
  private let evaluator: BudgetAlertEvaluator

  public init(
    context: any BudgetAlertContextProviding,
    scheduler: any BudgetNotificationScheduling,
    evaluator: BudgetAlertEvaluator = BudgetAlertEvaluator()
  ) {
    self.context = context
    self.scheduler = scheduler
    self.evaluator = evaluator
  }

  public func didCommit(affectedCategoryIDs: Set<UUID>) async {
    guard !affectedCategoryIDs.isEmpty else { return }

    let snapshot = await context.currentContext()
    let alerts = evaluator
      .evaluate(snapshot.progress, firedKeys: snapshot.firedKeys, settings: snapshot.settings)
      // The hook's payload, used. A category can only cross by having spend
      // added to it, so nothing is lost here. The one crossing this filter does
      // not see is a budget *lowered* under existing spend — no commit, no hook.
      // That path is U8's: it calls `evaluate` directly from `setBudget`.
      .filter { affectedCategoryIDs.contains($0.categoryID) }

    guard !alerts.isEmpty else { return }

    await context.recordFired(alerts)

    for alert in alerts where !alert.wasSuppressed {
      try? await scheduler.schedule(alert)
    }
  }
}
