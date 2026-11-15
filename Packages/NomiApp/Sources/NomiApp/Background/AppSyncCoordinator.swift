import Foundation
import NomiCore
import NomiIngest

#if os(iOS)
  import BackgroundTasks
#endif

/// Thrown by `AppSyncCoordinator.beginErase` when a sync or a reconcile has not
/// stopped by the deadline. Nothing was erased. `EraseError.busy` in NomiCore
/// (B5) is what callers see; B5 maps this one onto it.
public enum CoordinatorEraseError: Error, Sendable, Equatable {
  case busy
}

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

  /// A foreground reconciles only when the last reconcile is at least this old
  /// (M10). The sync still runs on every foreground.
  static let foregroundReconcileInterval: TimeInterval = 10 * 60

  /// How long after the *last* remote-change notification the reconcile runs.
  static let remoteChangeDebounce: TimeInterval = 2

  /// How often `beginErase` checks whether in-flight work has stopped. Its
  /// timeout is counted in these pauses, so the timeout is a floor on wall time.
  static let erasePollInterval: TimeInterval = 0.1

  private let mail: MailStack
  private let pipeline: IngestPipeline
  private let referenceData: (any ReferenceDataReconciling)?
  private let submitter: any BackgroundTaskSubmitting
  private let now: @Sendable () -> Date
  private let pause: @Sendable (TimeInterval) async throws -> Void
  private var isSyncing = false
  /// Closed by `beginErase` and open otherwise. A `Flag`, not actor state, because
  /// the scheduling calls are `nonisolated` and must read it synchronously.
  private let eraseGate = Flag()
  /// Reconciles, syncs, backfills and background runs in flight. `beginErase`
  /// waits for it to reach zero, so an erase never overlaps one of them.
  private var activeWork = 0
  private(set) var foregroundTask: Task<Void, Never>?
  private(set) var remoteChangeTask: Task<Void, Never>?
  private var lastReconcileAt: Date?
  private let onRemoteChangeSettled: (@MainActor @Sendable () -> Void)?
  /// Reconnects from the Keychain when a background task finds no mailbox. A
  /// cold launch by background refresh runs without `bootstrap()`, so nothing
  /// else has connected yet.
  private let ensureMailConnected: @Sendable () async -> Void

  /// `referenceData` is optional only so the coordinator tests that never touch
  /// reference rows need no container. `AppEnvironment` always passes one.
  ///
  /// `sleep` is the remote-change debounce's wait, injectable for the same
  /// reason `now` is: a test that has to wait out two real seconds is a test
  /// that is slow when it passes and flaky when CI is loaded.
  ///
  /// `onRemoteChangeSettled` runs once per debounced remote-change reconcile,
  /// after that reconcile returns, whether or not it changed anything. The
  /// import that caused the notification changed rows regardless of whether the
  /// reconcile then removed a duplicate, so this is where cached totals are
  /// dropped. `AppEnvironment` wires it to `cache.invalidate()`, not to
  /// `WriteCoordinator.didWrite`: a remote import must not run the budget
  /// observer, or a second device re-alerts on spend the first one already
  /// alerted on.
  public init(
    mail: MailStack,
    pipeline: IngestPipeline,
    referenceData: (any ReferenceDataReconciling)? = nil,
    submitter: any BackgroundTaskSubmitting = SystemBackgroundTaskSubmitter(),
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
      try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
    },
    onRemoteChangeSettled: (@MainActor @Sendable () -> Void)? = nil,
    ensureMailConnected: @escaping @Sendable () async -> Void = {}
  ) {
    self.mail = mail
    self.pipeline = pipeline
    self.referenceData = referenceData
    self.submitter = submitter
    self.now = now
    self.pause = sleep
    self.onRemoteChangeSettled = onRemoteChangeSettled
    self.ensureMailConnected = ensureMailConnected
  }

  // MARK: - Erase (B5a)

  /// Closes the gate, stops what is running, and waits until nothing can write
  /// behind it. Then cancels the pending background requests. The gate stays
  /// closed on success until `endErase()`.
  ///
  /// The background requests are cancelled only after the wait succeeds. The
  /// cancellations of the running tasks are signals and nothing more, so a
  /// `busy` erase leaves no trace except those signals. Cancelling the requests
  /// first would make a `busy` erase change the schedule.
  ///
  /// The wait is bounded by `timeout`, and the bound covers the tasks as well as
  /// the work. Awaiting a cancelled task's `.value` directly would hang on a task
  /// that ignores cancellation, and the erase would never report `busy`. So the
  /// tasks are joined in an unstructured task, and the wait polls for that join
  /// and for `activeWork`.
  public func beginErase(timeout: TimeInterval = 30) async throws {
    eraseGate.set(true)

    let inFlight = [foregroundTask, remoteChangeTask].compactMap { $0 }
    inFlight.forEach { $0.cancel() }
    foregroundTask = nil
    remoteChangeTask = nil

    let joined = Flag()
    Task {
      for task in inFlight { await task.value }
      joined.set(true)
    }

    var waited: TimeInterval = 0
    while !joined.isSet || activeWork > 0 {
      guard waited < timeout else {
        eraseGate.set(false)
        throw CoordinatorEraseError.busy
      }
      do {
        try await pause(Self.erasePollInterval)
      } catch {
        // Our own task was cancelled mid-wait. Nothing was erased, so reopen.
        eraseGate.set(false)
        throw error
      }
      waited += Self.erasePollInterval
    }

    submitter.cancelAll()
  }

  /// Reopens the gate after an erase, whether it succeeded or not.
  public func endErase() {
    eraseGate.set(false)
  }

  // MARK: - Reconcile

  /// R5's mandatory pass. CloudKit forbids unique constraints, so two devices
  /// can each create a locally-unique row for the same transaction — or insert
  /// the same seeded category — and sync merges them into two rows.
  ///
  /// "Mandatory, not defensive" is the design's wording: the corruption arrives
  /// while the app is *not* running, and nothing about it is visible until
  /// someone reads a total. So it runs on launch unconditionally, on a
  /// foreground that is ten minutes clear of the last one, and after a burst
  /// of remote changes settles — not on every foreground and every
  /// notification, which was a full-table scan each (M10).
  ///
  /// Transactions first, then reference data, so both share this scheduling.
  @discardableResult
  public func reconcile() async -> ReconcileResult {
    // While erasing, nothing reaches the pipeline or the reference data. A
    // reconcile already running is counted in `activeWork`, so the erase waits.
    guard !eraseGate.isSet else { return .empty }
    activeWork += 1
    defer { activeWork -= 1 }
    lastReconcileAt = now()
    let result: ReconcileResult
    do {
      result = try await pipeline.reconcile()
    } catch {
      // Swallowed for the same reason the pipeline's error is: nobody awaits a
      // reconcile, and the next one retries.
      NomiLog.sync.error("transaction reconcile failed: \(NomiLog.describe(error), privacy: .public)")
      result = .empty
    }
    if let referenceData {
      // Swallowed for the same reason the pipeline's error is: nobody awaits a
      // reconcile, and the next one retries. ReferenceDataReconciler has already
      // logged the failure where it happened; this line records that it was dropped here.
      await MainActor.run {
        do {
          _ = try referenceData.run()
        } catch {
          NomiLog.sync.error("reference data reconcile dropped: \(NomiLog.describe(error), privacy: .public)")
        }
      }
    }
    return result
  }

  /// `NSPersistentStoreRemoteChange` arrived.
  ///
  /// Coalesced: one reconcile, `remoteChangeDebounce` after the **last** call.
  /// A CloudKit import posts these in bursts, and each used to be its own
  /// full scan. Every call cancels the reconcile the previous one scheduled and
  /// schedules its own.
  public func remoteChangeObserved() {
    guard !eraseGate.isSet else { return }
    remoteChangeTask?.cancel()
    remoteChangeTask = Task { [weak self, pause = self.pause] in
      do {
        try await pause(AppSyncCoordinator.remoteChangeDebounce)
      } catch {
        NomiLog.sync.debug("remote-change reconcile superseded: \(NomiLog.describe(error), privacy: .public)")
        return  // superseded by a later notification
      }
      guard let self, !Task.isCancelled else { return }
      await self.reconcile()
      // Not from `reconcile()` itself: the launch and foreground reconciles
      // follow local writes or bootstrap's own `cache.invalidate()`, so only a
      // remote change needs this. Not reached on the cancelled early returns.
      if let hook = self.onRemoteChangeSettled { await hook() }
    }
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
  ///
  /// Always syncs. Reconciles first only when the last reconcile is at least
  /// `foregroundReconcileInterval` old — whoever ran it: launch, a foreground,
  /// or a remote change.
  public func didBecomeActive() {
    guard !eraseGate.isSet else { return }
    foregroundTask?.cancel()
    let reconcileIsDue = lastReconcileAt.map {
      now().timeIntervalSince($0) >= Self.foregroundReconcileInterval
    } ?? true
    foregroundTask = Task { [weak self] in
      guard let self else { return }
      if reconcileIsDue {
        await self.reconcile()
      }
      await self.syncIfIdle()
    }
  }

  /// `scenePhase` became `.background`. Not `.inactive`: see `NomiAppScene`.
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

  /// What a sync request actually did.
  ///
  /// It used to return nothing and swallow everything through `try?`, which made
  /// two very different outcomes identical to every caller: a sync that ran, and
  /// a sync that was refused because no mailbox is connected yet. The second is
  /// the launch case — `didBecomeActive` fires before `bootstrap()` has
  /// reconnected — and losing it is how the first sync after a launch went
  /// missing.
  public enum SyncAttempt: Sendable, Equatable {
    case ran
    case alreadyRunning
    /// Refused: there is no connected mailbox. A sync that is *owed*, not one
    /// that failed, and `syncAfterConnect()` is what settles it.
    case noMailboxConnected
    case failed
  }

  @discardableResult
  func syncIfIdle() async -> SyncAttempt {
    guard !eraseGate.isSet, !isSyncing else { return .alreadyRunning }
    isSyncing = true
    activeWork += 1
    defer {
      isSyncing = false
      activeWork -= 1
    }

    do {
      _ = try await mail.syncNow()
      return .ran
    } catch let error as IMAPTransportError where error == .notConnected {
      // Named rather than swallowed. Nothing is wrong and there is nothing to
      // report to the user — there is simply no mailbox yet.
      NomiLog.sync.debug("sync owed, no mailbox connected: \(NomiLog.describe(error), privacy: .public)")
      return .noMailboxConnected
    } catch {
      // Other errors are the connection service's to report: it yields `.failed`
      // on its state stream, which `SyncStatusRow` and `SettingsScreen` render.
      // Re-throwing here would have nowhere to go — nobody awaits a scene phase.
      NomiLog.sync.error("sync failed: \(NomiLog.describe(error), privacy: .public)")
      return .failed
    }
  }

  /// The sync that follows a reconnect, issued by `AppEnvironment.bootstrap()`
  /// once `reconnectFromKeychain` has returned.
  ///
  /// Before this existed, launch ended at the reconnect. `didBecomeActive` had
  /// already run — it fires on the first `.active` scene phase, which is before
  /// `bootstrap()` finishes — found no mailbox, and swallowed the
  /// `.notConnected`. So nothing synced until the user backgrounded and
  /// foregrounded the app by hand.
  ///
  /// **It waits out that in-flight foreground task rather than being dropped by
  /// the idle guard.** A `didBecomeActive` that got there first is, by
  /// definition, the sync that ran with nothing connected; letting the guard
  /// treat it as "a sync is already happening" is the same bug wearing a
  /// different hat. Awaiting inside the actor is safe — the actor suspends at
  /// the await, so the foreground task's own actor-isolated work can proceed.
  @discardableResult
  public func syncAfterConnect() async -> SyncAttempt {
    await foregroundTask?.value
    return await syncIfIdle()
  }

  /// The backfill half of `syncIfIdle`, guarded by the same flag so a backfill
  /// and an incremental sync cannot run over each other.
  ///
  /// Goes through `mail.service` rather than a `MailStack.backfill(...)`
  /// convenience. `MailStack.startBackfill` used to exist, had no callers, and
  /// persisted the cursor while `service.startBackfill` did not — two doors with
  /// different behaviour. It was deleted rather than fixed, so this is the same
  /// call `BackfillScreen` makes.
  ///
  /// Reports the same `SyncAttempt` as `syncIfIdle()`, so a background backfill
  /// that finds no mailbox is owed rather than failed, and is retried after a
  /// reconnect exactly as a refresh is.
  private func backfillIfIdle() async -> SyncAttempt {
    guard !eraseGate.isSet, !isSyncing else { return .alreadyRunning }
    isSyncing = true
    activeWork += 1
    defer {
      isSyncing = false
      activeWork -= 1
    }

    do {
      try await mail.service.startBackfill(months: Self.backfillMonths)
      return .ran
    } catch let error as IMAPTransportError where error == .notConnected {
      NomiLog.sync.debug("backfill owed, no mailbox connected: \(NomiLog.describe(error), privacy: .public)")
      return .noMailboxConnected
    } catch {
      NomiLog.sync.error("backfill failed: \(NomiLog.describe(error), privacy: .public)")
      return .failed
    }
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
    guard !eraseGate.isSet else { return }
    submitter.submit(.refresh, identifier: TaskIdentifier.refresh, notBefore: interval)
  }

  /// Ask for the interrupted backfill to be finished.
  ///
  /// A much shorter floor than the refresh's fifteen minutes: this is the first
  /// run, the user has just watched a progress bar, and the dashboard is empty
  /// until the scan completes. It is still only a floor.
  public nonisolated func scheduleBackgroundBackfill(after interval: TimeInterval = 60) {
    guard !eraseGate.isSet else { return }
    submitter.submit(.backfill, identifier: TaskIdentifier.backfill, notBefore: interval)
  }

  /// Runs one background task to completion and tells iOS how it went.
  ///
  /// `setTaskCompleted(success:)` must be called exactly once, including on the
  /// expiration path — an unanswered task counts against the app's future
  /// scheduling budget, which is the mechanism that quietly turns background
  /// refresh off for good.
  public func run(_ work: BackgroundWork) async {
    // Erasing: the work is refused and reported as not done. Nothing here is
    // rescheduled either, so iOS is not asked for another window.
    guard !eraseGate.isSet else {
      work.setCompleted(success: false)
      return
    }
    // Created before the handler is installed, and that ordering is safe rather
    // than lucky: `Task {}` written inside an actor's method inherits this
    // actor's executor, so its body cannot begin until `run(_:)` suspends, and
    // `run(_:)` does not suspend between here and `setExpirationHandler`.
    let task = Task<Bool, Never> { [weak self] in
      guard let self else { return false }
      return await self.perform(work.kind)
    }

    // The work `run(_:)` is actually awaiting. This used to cancel
    // `foregroundTask`, which is nil on every path that reaches here — the app
    // is not in the foreground when a BGTask fires, so nothing ever set it — so
    // expiration cancelled nothing and the sync ran on until the OS killed the
    // process. An expiration handler that does not stop the work is worse than
    // none: over-running is precisely what spends the scheduling budget the
    // `setCompleted` contract is protecting.
    work.setExpirationHandler { task.cancel() }

    let performSucceeded = await task.value

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
    // short, or when the sync itself failed. iOS counts an unsuccessful task
    // against the app's scheduling budget, so a failure is reported as one.
    work.setCompleted(success: !task.isCancelled && performSucceeded)
  }

  /// Routes by `kind`.
  ///
  /// It did not. `run(_:)` read `kind` only to decide whether to re-schedule,
  /// so a `.backfill` task — registered, permitted in `Info.plist`, and asked
  /// for by nobody — would have run a plain incremental sync: `uids(after:)`
  /// from the cursor, which returns nothing the interrupted backfill had not
  /// already passed. The months it never reached would have stayed unfetched
  /// forever.
  ///
  /// Returns whether the work succeeded. A sync that found no mailbox after one
  /// reconnect attempt is still success: nothing was saved and nothing is owed,
  /// because the user never connected mail. Only `.failed` is a failure.
  private func perform(_ kind: BackgroundWork.Kind) async -> Bool {
    // Checked and counted with no suspension between, so `beginErase` sees either
    // this work in `activeWork` or the closed gate that refuses it. Counting the
    // whole run also covers `ensureMailConnected`, which is not counted otherwise.
    guard !eraseGate.isSet else { return false }
    activeWork += 1
    defer { activeWork -= 1 }
    await reconcile()

    var attempt = await runSync(kind)
    if attempt == .noMailboxConnected {
      // A cold background launch has not run `bootstrap()`, so the mailbox
      // may simply not be connected yet. Connect from the Keychain and try once
      // more. Without this, the refresh finds no mailbox, reports nothing, and
      // the user's mail stays stale until the app is opened by hand.
      await ensureMailConnected()
      attempt = await runSync(kind)
    }

    switch attempt {
    case .ran, .alreadyRunning, .noMailboxConnected:
      return true
    case .failed:
      return false
    }
  }

  private func runSync(_ kind: BackgroundWork.Kind) async -> SyncAttempt {
    switch kind {
    case .refresh:
      return await syncIfIdle()
    case .backfill:
      return await backfillIfIdle()
    }
  }
}

/// A boolean that can be read and written from any isolation. The erase gate is
/// read by `nonisolated` scheduling calls, and the join latch is set from an
/// unstructured task. Both need a value that is not behind the actor.
private final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Bool

  init(_ value: Bool = false) {
    self.value = value
  }

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set(_ newValue: Bool) {
    lock.lock()
    value = newValue
    lock.unlock()
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
  /// Cancels every pending request for both identifiers (B5a, I-13 G4). A no-op
  /// for conformers that never schedule anything.
  func cancelAll()
}

extension BackgroundTaskSubmitting {
  public func cancelAll() {}
}

/// The real one. A no-op off iOS, where there is no scheduler to submit to.
public struct SystemBackgroundTaskSubmitter: BackgroundTaskSubmitting {
  public init() {}

  /// Cancels the pending request for each identifier. `cancel` is a no-op for an
  /// identifier with nothing queued, and off iOS there is nothing to cancel.
  public func cancelAll() {
    #if os(iOS)
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppSyncCoordinator.TaskIdentifier.refresh)
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: AppSyncCoordinator.TaskIdentifier.backfill)
    #endif
  }

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
      do {
        try BGTaskScheduler.shared.submit(request)
      } catch {
        NomiLog.sync.notice("background task not submitted: \(NomiLog.describe(error), privacy: .public)")
      }
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
