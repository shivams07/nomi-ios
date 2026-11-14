import Foundation

/// Everything the evaluator needs, read at one instant.
///
/// **Not `Equatable`, deliberately.** `BudgetProgress` is not `Equatable`, so
/// the conformance cannot be synthesised — and the alternative, adding it to
/// `BudgetProgress` in `Contracts/Types.swift`, means editing a shared contract
/// for a conformance nothing in the repo uses. Nothing compares two contexts:
/// it is constructed by U8's provider, read once by the evaluator, and dropped.
/// If a caller ever does need equality, add it to `BudgetProgress` in the
/// contract rather than hand-writing `==` here.
public struct BudgetAlertContext: Sendable {
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
  /// Called *after* each unsuppressed alert was handed to an authorised centre
  /// without error, with the suppressed ones alongside — see `BudgetAlertObserver`.
  /// An alert the centre refused is not in the list, so it is retried.
  func recordFired(_ alerts: [BudgetAlert]) async
}

/// Joins the evaluator to the scheduler on U4's commit hook. U4 must not know
/// budgets exist; U8 registers this.
///
/// Ordering is deliberate, and it is the reverse of what this type used to do.
/// An alert is recorded as fired only after the centre has accepted it: the log
/// row is written once `schedule` has returned without throwing. Recording first
/// meant a centre that refused the alert (permission revoked, or `add` throwing)
/// still silenced the category for the rest of the month, so the user was never
/// told. The cost of this order is that a failed alert can fire again on the next
/// commit, which is a repeat rather than a loss. The request identifier is the
/// alert's `logKey`, so the centre replaces a repeat rather than stacking it.
///
/// The centre gives no delivery receipt, so "accepted" means `add` returned
/// without throwing to a centre that reported itself authorised. An unauthorised
/// centre records nothing at all, so the alert can still fire once permission
/// exists within the same period.
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

    let suppressed = alerts.filter(\.wasSuppressed)
    let pending = alerts.filter { !$0.wasSuppressed }

    // Without permission nothing is shown, so nothing is recorded either: the
    // alert stays open for the rest of the period and fires on a later commit
    // once the user has granted it.
    if !pending.isEmpty {
      guard await scheduler.isAuthorized() else { return }
    }

    var delivered: [BudgetAlert] = []
    for alert in pending {
      do {
        try await scheduler.schedule(alert)
        delivered.append(alert)
      } catch {
        // Not recorded, so the next commit in this period retries it.
      }
    }

    await context.recordFired(suppressed + delivered)
  }
}
