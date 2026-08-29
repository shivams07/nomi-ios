import Foundation
import NomiCore
import NomiIngest

#if os(iOS)
  import BackgroundTasks
#endif

/// Everything that runs because of *time* rather than because of a tap: the
/// launch reconcile, the foreground sync, the background refresh, and the
/// remote-change reconcile.
///
/// It is an actor so the "is a sync already running" question has one answer.
/// Two syncs racing would each fetch the same UIDs and each hand them to the
/// pipeline; the pipeline would absorb the duplicate as a no-op, so nothing
/// would break — it would just cost the user two of everything for no gain.
public actor AppSyncCoordinator {
  /// Declared in `App/Info.plist` under `BGTaskSchedulerPermittedIdentifiers`
  /// (U0 wrote them up front). An identifier not in that array is a crash at
  /// registration, not a warning, so these strings must match it exactly.
  public enum TaskIdentifier {
    public static let refresh = "com.shivams07.nomi.refresh"
    public static let backfill = "com.shivams07.nomi.backfill"
  }

  private let mail: MailStack
  private let pipeline: IngestPipeline
  private var isSyncing = false
  private var foregroundTask: Task<Void, Never>?

  public init(mail: MailStack, pipeline: IngestPipeline) {
    self.mail = mail
    self.pipeline = pipeline
  }

  // MARK: - Reconcile

  /// R5's mandatory pass. CloudKit forbids unique constraints, so two devices
  /// can each create a locally-unique row for the same transaction and sync
  /// merges them into two rows.
  ///
  /// "Mandatory, not defensive" is the design's wording, and it is why this is
  /// called on launch and on every foreground rather than only when something
  /// looks wrong: the corruption arrives while the app is *not* running, and
  /// nothing about it is visible until someone reads a total.
  @discardableResult
  public func reconcile() async -> ReconcileResult {
    (try? await pipeline.reconcile()) ?? .empty
  }

  // MARK: - Foreground / background

  /// `scenePhase` became `.active`.
  ///
  /// The design's "IDLE start/stop" belongs here and is **not implemented**,
  /// because there is nothing to idle: `MailConnectionService` declares no IDLE
  /// method — it was to be internal to the `MailFetching` implementation, which
  /// does not exist (see `UnavailableMailFetcher`). What is implemented is the
  /// lifecycle the IDLE loop would have hung off: sync on activate, stop on
  /// background. When a transport lands, IDLE starts and stops on these same
  /// two calls.
  public func didBecomeActive() {
    foregroundTask?.cancel()
    foregroundTask = Task { [weak self] in
      guard let self else { return }
      await self.reconcile()
      await self.syncIfIdle()
    }
  }

  /// `scenePhase` left `.active`.
  ///
  /// The in-flight sync is cancelled rather than left to finish. iOS gives a
  /// backgrounding app seconds, not minutes, and a sync killed mid-batch by the
  /// OS is worse than one cancelled cleanly: `MailSyncEngine` advances its
  /// cursor only past completed batches either way, but a cancelled task
  /// releases the connection instead of holding it into suspension.
  public func didEnterBackground() {
    foregroundTask?.cancel()
    foregroundTask = nil
    scheduleBackgroundRefresh()
  }

  private func syncIfIdle() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    // Errors are the connection service's to report: it yields `.failed` on
    // its state stream, which `SyncStatusRow` and `SettingsScreen` render.
    // Re-throwing here would have nowhere to go — nobody awaits a scene phase.
    _ = try? await mail.syncNow()
  }

  // MARK: - BGTaskScheduler

  /// Must be called before the app finishes launching, hence from
  /// `NomiAppScene.init` rather than from a `.task`. Registering later is an
  /// exception, not a no-op.
  public static func registerBackgroundTasks(
    handler: @escaping @Sendable (BackgroundWork) -> Void
  ) {
    #if os(iOS)
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: TaskIdentifier.refresh,
        using: nil
      ) { task in
        handler(BackgroundWork(task: task, kind: .refresh))
      }
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: TaskIdentifier.backfill,
        using: nil
      ) { task in
        handler(BackgroundWork(task: task, kind: .backfill))
      }
    #endif
  }

  /// Ask for a refresh. iOS decides if and when — `earliestBeginDate` is a
  /// floor, never a schedule, and on a device where the user rarely opens the
  /// app it may never fire at all. §0.2 already establishes that the 1–2 minute
  /// freshness criterion is not achievable this way; this is best-effort
  /// catch-up, not delivery.
  public nonisolated func scheduleBackgroundRefresh(after interval: TimeInterval = 15 * 60) {
    #if os(iOS)
      let request = BGAppRefreshTaskRequest(identifier: TaskIdentifier.refresh)
      request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
      // Throws when the identifier is not permitted, when too many are already
      // queued, or in the simulator, which has no scheduler. None of those are
      // worth failing a launch over.
      try? BGTaskScheduler.shared.submit(request)
    #endif
  }

  /// Runs one background task to completion and tells iOS how it went.
  ///
  /// `setTaskCompleted(success:)` must be called exactly once, including on the
  /// expiration path — an unanswered task counts against the app's future
  /// scheduling budget, which is the mechanism that quietly turns background
  /// refresh off for good.
  public func run(_ work: BackgroundWork) async {
    work.setExpirationHandler { [weak self] in
      Task { await self?.cancelForeground() }
    }

    await reconcile()
    await syncIfIdle()

    if work.kind == .refresh {
      scheduleBackgroundRefresh()
    }
    work.setCompleted(success: true)
  }

  private func cancelForeground() {
    foregroundTask?.cancel()
    foregroundTask = nil
  }
}

/// A background task, wrapped so `AppSyncCoordinator` compiles on macOS — where
/// `swift test` runs this package and `BackgroundTasks` is not available.
///
/// The wrapper is not indirection for its own sake: without it every call site
/// needs its own `#if os(iOS)`, and the non-iOS branch of each one is a place
/// for the two paths to drift.
public struct BackgroundWork: @unchecked Sendable {
  public enum Kind: Sendable {
    case refresh
    case backfill
  }

  public let kind: Kind

  #if os(iOS)
    private let task: BGTask

    init(task: BGTask, kind: Kind) {
      self.task = task
      self.kind = kind
    }

    public func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
      task.expirationHandler = handler
    }

    public func setCompleted(success: Bool) {
      task.setTaskCompleted(success: success)
    }
  #else
    public init(kind: Kind) {
      self.kind = kind
    }

    public func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {}
    public func setCompleted(success: Bool) {}
  #endif
}
