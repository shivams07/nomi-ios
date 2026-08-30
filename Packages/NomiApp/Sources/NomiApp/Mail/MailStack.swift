import Foundation
import NomiCore
import NomiIngest

/// The assembled mail side: engine, connection service, and the cursor's
/// persistence.
///
/// `MailSyncEngine.cursor` is `public private(set)` and settable only at init —
/// U2's `MailFetching` doc says in as many words that it is "persisted by U8;
/// U2 only reads and returns it". Nothing calls back when it moves, so the
/// cursor is read and written around each sync from here.
///
/// **Around each sync means every sync, and until §D1 it did not.** The
/// persisting wrapper was `MailStack.syncNow()`, while `MailStack.service` —
/// the thing handed to every screen — was the broadcaster over the *raw*
/// `IMAPMailConnectionService`. Only `AppSyncCoordinator` went through the
/// persisting door. `SettingsScreen`'s "Sync now", `ConnectMailScreen` and
/// `BackfillScreen` all went round it, and the cursor those syncs moved was
/// dropped: the next launch re-read the mailbox from wherever the last
/// *background* sync happened to have reached.
///
/// The fix is ordering, not new behaviour. `CursorPersistingMailConnectionService`
/// is interposed **below** the broadcaster, so there is no longer a route into a
/// sync that skips it, and `startBackfill` is not duplicated here as a second
/// door.
public actor MailStack {
  /// What every screen is handed. Not the raw connection service — see
  /// `BroadcastingMailConnectionService`: four merged screens each open a
  /// `for await` over `.state`, and `AsyncStream` is single-consumer.
  ///
  /// It is also the only sync entry point in the app now. `syncNow()` below
  /// forwards to it rather than reimplementing anything.
  public let service: BroadcastingMailConnectionService

  private let persisting: CursorPersistingMailConnectionService

  public init(
    fetcher: any MailFetching,
    pipeline: any DraftIngesting,
    credentials: any MailCredentialStoring,
    preferences: any KeyValueStoring
  ) {
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: pipeline,
      cursor: Self.loadCursor(from: preferences)
    )

    let connectionService = IMAPMailConnectionService(
      fetcher: fetcher,
      engine: engine,
      credentials: credentials
    )

    let persisting = CursorPersistingMailConnectionService(
      upstream: connectionService,
      engine: engine,
      preferences: preferences
    )
    self.persisting = persisting
    self.service = BroadcastingMailConnectionService(upstream: persisting)
  }

  /// Sync, then persist wherever the engine got to.
  ///
  /// A thin forward on purpose: `AppSyncCoordinator` calls this and every screen
  /// calls `service.syncNow()`, and after §D1 those are the same code path. The
  /// persistence lives one layer down, described there.
  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    try await service.syncNow()
  }

  /// Whether a backfill has been started and has not run to completion — either
  /// because one is in flight right now, or because the last one stopped
  /// part-way.
  ///
  /// `AppSyncCoordinator` reads it to decide whether to ask iOS for the backfill
  /// processing task. **In memory, not in `preferences`, and that is a real
  /// limit**: the path that matters survives it, because `didEnterBackground()`
  /// runs on the way into suspension while this object is still alive, but a
  /// crash or a force-quit mid-backfill is not recovered — the next launch has
  /// no idea a scan was unfinished. Persisting it needs a key in
  /// `PreferenceKey`, which is in `Support/KeyValueStore.swift` and outside this
  /// unit's file list.
  public var backfillIsUnfinished: Bool { persisting.backfillIsUnfinished }

  /// Restores the last session on launch, so a returning user is connected
  /// without retyping an app password. Silent by design: a missing credential
  /// is the ordinary "never connected" case, not an error to surface.
  public func reconnectFromKeychain(_ store: any MailCredentialStoring) async {
    // One `guard let`, not two. `load()` returns `IMAPCredentials?` and `try?`
    // flattens rather than nesting, so there is no second layer to unwrap —
    // "no credential stored" and "the keychain read failed" arrive as the same
    // nil, and both mean the same thing here: nothing to reconnect to.
    guard let credentials = try? store.load() else { return }
    try? await service.connect(credentials)
  }

  private static func loadCursor(from preferences: any KeyValueStoring) -> MailSyncCursor? {
    guard let data = preferences.data(forKey: PreferenceKey.mailSyncCursor) else { return nil }
    return try? JSONDecoder().decode(MailSyncCursor.self, from: data)
  }
}

/// Forwards to the real connection service and writes the engine's cursor down
/// afterwards, so that persisting it is not something a caller has to remember.
///
/// **It sits below `BroadcastingMailConnectionService`, and that is the whole
/// point.** The broadcaster is what screens hold; wrapping it from above would
/// leave the unpersisting service reachable underneath, which is the bug this
/// type exists to close.
///
/// Not an actor. Its own state is one `Bool` behind a lock, and everything else
/// it does is forwarding — an actor here would add a hop to every sync to
/// serialise a flag that `NSLock` serialises for free, and `MailSyncEngine` is
/// already the actor that makes the cursor read consistent.
final class CursorPersistingMailConnectionService: MailConnectionService, @unchecked Sendable {
  private let upstream: any MailConnectionService
  private let engine: MailSyncEngine
  private let preferences: any KeyValueStoring

  private let lock = NSLock()
  private var unfinishedBackfill = false

  init(
    upstream: any MailConnectionService,
    engine: MailSyncEngine,
    preferences: any KeyValueStoring
  ) {
    self.upstream = upstream
    self.engine = engine
    self.preferences = preferences
  }

  var state: AsyncStream<MailConnectionState> { upstream.state }
  var backfillProgress: AsyncStream<BackfillProgress> { upstream.backfillProgress }

  var backfillIsUnfinished: Bool {
    lock.lock()
    defer { lock.unlock() }
    return unfinishedBackfill
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    try await upstream.connect(credentials)
  }

  func disconnect() async throws {
    try await upstream.disconnect()
  }

  /// The cursor is saved **after** the call whether it threw or not, and that is
  /// deliberate: `MailSyncEngine` advances only to the end of a completed
  /// prefix, so a partial sync leaves a cursor that is correct and worth
  /// keeping. Discarding it on error would re-fetch every completed batch on the
  /// next run — the exact cost §2.17's prefix rule exists to avoid.
  ///
  /// Written out rather than `defer { Task { await persistCursor() } }`, which
  /// is the shape this had. `defer` cannot await, so the persistence became a
  /// detached task that outlived the call: `syncNow()` returned, and the write
  /// landed at some later unordered moment. Nothing ever waited for it — not the
  /// caller, and not a test.
  @discardableResult
  func syncNow() async throws -> SyncSummary {
    do {
      let summary = try await upstream.syncNow()
      await persistCursor()
      return summary
    } catch {
      await persistCursor()
      throw error
    }
  }

  /// Six months at first run (§1.3), and the one call in this app that can be
  /// interrupted with real work left to do — it is minutes long and the user is
  /// free to leave the screen or the app while it runs.
  ///
  /// The flag is set *before* the call rather than only on failure. Suspension
  /// is not a failure: iOS freezes the task mid-await, so nothing throws and
  /// nothing returns, and a flag that only recorded thrown errors would read
  /// `false` for the exact case it exists to catch.
  ///
  /// **A backfill the user cancelled and one iOS interrupted are the same event
  /// here.** `MailConnectionService` has no cancel/resume — `BackfillScreen`
  /// says so in its own comment and wraps this call in a `Task` it cancels
  /// instead — so both arrive as a thrown `CancellationError` and both leave the
  /// flag set. The consequence is that pressing Cancel does not stop the
  /// background task from later resuming the scan. Re-ingesting is a no-op in
  /// U4, so the cost is bandwidth rather than duplicate rows, but it is a
  /// behaviour change and telling the two apart needs a contract this unit does
  /// not have.
  func startBackfill(months: Int) async throws {
    setUnfinishedBackfill(true)
    do {
      try await upstream.startBackfill(months: months)
      await persistCursor()
      setUnfinishedBackfill(false)
    } catch IMAPTransportError.notConnected {
      // Nothing started, so there is nothing to resume. Leaving the flag set
      // would ask iOS for a processing task that can only fail the same way,
      // once per backgrounding, for as long as the mailbox stays disconnected.
      setUnfinishedBackfill(false)
      throw IMAPTransportError.notConnected
    } catch {
      await persistCursor()
      throw error
    }
  }

  private func persistCursor() async {
    let cursor = await engine.cursor
    preferences.set(try? JSONEncoder().encode(cursor), forKey: PreferenceKey.mailSyncCursor)
  }

  private func setUnfinishedBackfill(_ value: Bool) {
    lock.lock()
    unfinishedBackfill = value
    lock.unlock()
  }
}
