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

  /// §1.3's six months. The same number `OnboardingFlow` passes to
  /// `BackfillScreen`; a resumed backfill re-walks the same window, and the
  /// months it already covered cost one re-fetch each that U4's dedupe no-ops
  /// away.
  static let backfillMonths = 6

  private let mail: MailStack
  private let pipeline: IngestPipeline
  private let submitter: any BackgroundTaskSubmitting
  private var isSyncing = false
  private var foregroundTask: Task<Void, Never>?

  public init(
    mail: MailStack,
    pipeline: IngestPipeline,
    submitter: any BackgroundTaskSubmitting = SystemBackgroundTaskSubmitter()
  ) {
    self.mail = mail
    self.pipeline = pipeline
    self.submitter = submitter
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
  /// The design's "IDLE start/stop" belongs here and is **not implemented**.
  /// U2c landed the transport, so "there is no socket to idle on" is no longer
  /// the reason. The reason now is that nothing here can reach an IDLE loop:
  /// neither `MailFetching` nor `MailConnectionService` declares an IDLE entry
  /// point, so wiring one changes U2's and U1's contracts as well as this file.
  /// `IMAPCommand.idle(tag:)` and `idleDoneWireText` are written and waiting on
  /// that.
  ///
  /// What *is* implemented is the lifecycle the IDLE loop would hang off: sync
  /// on activate, stop on background. IDLE would start and stop on these same
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
  ///
  /// A *backfill* is not cancelled here and is not this coordinator's task to
  /// cancel — `BackfillScreen` owns it. What happens to it is that the process
  /// is suspended with the scan part-done, which is the one case
  /// `MailStack.backfillIsUnfinished` exists to report. This is the last moment
  /// anything can be asked of iOS on its behalf, so the processing task is
  /// submitted here.
  public func didEnterBackground() async {
    foregroundTask?.cancel()
    foregroundTask = nil
    scheduleBackgroundRefresh()

    if await mail.backfillIsUnfinished {
      scheduleBackgroundBackfill()
    }
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

  /// The backfill half of `syncIfIdle`, guarded by the same flag so a backfill
  /// and an incremental sync cannot run over each other.
  ///
  /// Goes through `mail.service` rather than a `MailStack.backfill(...)`
  /// convenience. `MailStack.startBackfill` used to exist, had no callers, and
  /// persisted the cursor while `service.startBackfill` did not — two doors with
  /// different behaviour. It was deleted rather than fixed, so this is the same
  /// call `BackfillScreen` makes.
  private func backfillIfIdle() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }
    try? await mail.service.startBackfill(months: Self.backfillMonths)
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
    submitter.submit(.refresh, identifier: TaskIdentifier.refresh, notBefore: interval)
  }

  /// Ask for the interrupted backfill to be finished.
  ///
  /// A much shorter floor than the refresh's fifteen minutes: this is the first
  /// run, the user has just watched a progress bar, and the dashboard is empty
  /// until the scan completes. It is still only a floor.
  public nonisolated func scheduleBackgroundBackfill(after interval: TimeInterval = 60) {
    submitter.submit(.backfill, identifier: TaskIdentifier.backfill, notBefore: interval)
  }

  /// Runs one background task to completion and tells iOS how it went.
  ///
  /// `setTaskCompleted(success:)` must be called exactly once, including on the
  /// expiration path — an unanswered task counts against the app's future
  /// scheduling budget, which is the mechanism that quietly turns background
  /// refresh off for good.
  public func run(_ work: BackgroundWork) async {
    // Created before the handler is installed, and that ordering is safe rather
    // than lucky: `Task {}` written inside an actor's method inherits this
    // actor's executor, so its body cannot begin until `run(_:)` suspends, and
    // `run(_:)` does not suspend between here and `setExpirationHandler`.
    let task = Task { [weak self] in
      guard let self else { return }
      await self.perform(work.kind)
    }

    // The work `run(_:)` is actually awaiting. This used to cancel
    // `foregroundTask`, which is nil on every path that reaches here — the app
    // is not in the foreground when a BGTask fires, so nothing ever set it — so
    // expiration cancelled nothing and the sync ran on until the OS killed the
    // process. An expiration handler that does not stop the work is worse than
    // none: over-running is precisely what spends the scheduling budget the
    // `setCompleted` contract is protecting.
    work.setExpirationHandler { task.cancel() }

    await task.value

    if work.kind == .refresh {
      scheduleBackgroundRefresh()
    }
    // Whatever the work was, if a backfill is still unfinished it needs another
    // window — including the case where *this* task was the backfill and
    // expiration cut it short.
    if await mail.backfillIsUnfinished {
      scheduleBackgroundBackfill()
    }

    // Exactly once, on every path including expiration: the handler above only
    // cancels, it never completes. `success` is false when the work was cut
    // short, because it was.
    work.setCompleted(success: !task.isCancelled)
  }

  /// Routes by `kind`.
  ///
  /// It did not. `run(_:)` read `kind` only to decide whether to re-schedule,
  /// so a `.backfill` task — registered, permitted in `Info.plist`, and asked
  /// for by nobody — would have run a plain incremental sync: `uids(after:)`
  /// from the cursor, which returns nothing the interrupted backfill had not
  /// already passed. The months it never reached would have stayed unfetched
  /// forever.
  private func perform(_ kind: BackgroundWork.Kind) async {
    await reconcile()

    switch kind {
    case .refresh:
      await syncIfIdle()
    case .backfill:
      await backfillIfIdle()
    }
  }
}

/// The submit half of `BGTaskScheduler`, behind a protocol.
///
/// Not abstraction for its own sake. `BGTaskScheduler` does not exist on macOS,
/// where `swift test` runs this package, so without a seam "did an interrupted
/// backfill ask iOS to finish it?" is a question no test on this project can
/// put — and R1 of the fix-scope design is that not being able to put those
/// questions is how these bugs shipped in the first place.
public protocol BackgroundTaskSubmitting: Sendable {
  /// `kind` chooses the request type, not just the identifier. They are
  /// different classes and iOS treats them differently — see
  /// `SystemBackgroundTaskSubmitter`.
  func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval)
}

/// The real one. A no-op off iOS, where there is no scheduler to submit to.
public struct SystemBackgroundTaskSubmitter: BackgroundTaskSubmitting {
  public init() {}

  public func submit(_ kind: BackgroundWork.Kind, identifier: String, notBefore: TimeInterval) {
    #if os(iOS)
      let request: BGTaskRequest
      switch kind {
      case .refresh:
        request = BGAppRefreshTaskRequest(identifier: identifier)
      case .backfill:
        // A `BGProcessingTaskRequest`, not an app-refresh one: a six-month scan
        // is minutes of work and an app-refresh task is given roughly thirty
        // seconds. Network is required because there is nothing to do without a
        // mailbox; external power deliberately is not, since "wait until it is
        // on the charger" would mean a first run whose dashboard fills up
        // overnight.
        let processing = BGProcessingTaskRequest(identifier: identifier)
        processing.requiresNetworkConnectivity = true
        processing.requiresExternalPower = false
        request = processing
      }
      request.earliestBeginDate = Date(timeIntervalSinceNow: notBefore)
      // Throws when the identifier is not permitted, when too many are already
      // queued, or in the simulator, which has no scheduler. None of those are
      // worth failing a launch over.
      try? BGTaskScheduler.shared.submit(request)
    #endif
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
    /// Off iOS these two calls used to be empty bodies, which made the one
    /// property of `run(_:)` that actually matters — `setCompleted` is called
    /// exactly once, including when the task expires — untestable on the only
    /// platform this package's tests run on. So the non-iOS branch records
    /// instead of discarding. It is a stand-in for `BGTask`, which is what this
    /// whole type is.
    private let record: BackgroundWorkRecord

    public init(kind: Kind) {
      self.kind = kind
      self.record = BackgroundWorkRecord()
    }

    init(kind: Kind, record: BackgroundWorkRecord) {
      self.kind = kind
      self.record = record
    }

    public func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
      record.setExpirationHandler(handler)
    }

    public func setCompleted(success: Bool) {
      record.recordCompletion(success: success)
    }
  #endif
}

#if !os(iOS)
  /// What `BGTask` does for us on iOS: hold the expiration handler so the system
  /// can fire it, and notice being completed. A reference type because
  /// `BackgroundWork` is a struct the caller copies.
  final class BackgroundWorkRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var expirationHandler: (@Sendable () -> Void)?
    private var completions: [Bool] = []

    init() {}

    /// Every `setCompleted(success:)` this task received, in order. The
    /// assertion is on the *count* as much as the value: iOS penalises a task
    /// that is completed twice as surely as one never completed at all.
    var recordedCompletions: [Bool] {
      lock.lock()
      defer { lock.unlock() }
      return completions
    }

    /// Stands in for iOS deciding the task has had long enough.
    func expire() {
      lock.lock()
      let handler = expirationHandler
      lock.unlock()
      handler?()
    }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
      lock.lock()
      expirationHandler = handler
      lock.unlock()
    }

    func recordCompletion(success: Bool) {
      lock.lock()
      completions.append(success)
      lock.unlock()
    }
  }
#endif
