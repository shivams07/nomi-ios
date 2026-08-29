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
public actor MailStack {
  /// What every screen is handed. Not `connectionService` — see
  /// `BroadcastingMailConnectionService`: four merged screens each open a
  /// `for await` over `.state`, and `AsyncStream` is single-consumer.
  public let service: BroadcastingMailConnectionService

  private let connectionService: IMAPMailConnectionService
  private let engine: MailSyncEngine
  private let preferences: any KeyValueStoring

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
    self.engine = engine
    self.preferences = preferences

    let connectionService = IMAPMailConnectionService(
      fetcher: fetcher,
      engine: engine,
      credentials: credentials
    )
    self.connectionService = connectionService
    self.service = BroadcastingMailConnectionService(upstream: connectionService)
  }

  /// Sync, then persist wherever the engine got to.
  ///
  /// The cursor is saved **after** the call whether it threw or not, and that
  /// is deliberate: `MailSyncEngine` advances only to the end of a completed
  /// prefix, so a partial backfill leaves a cursor that is correct and worth
  /// keeping. Discarding it on error would re-fetch every completed batch on
  /// the next run — the exact cost §2.17's prefix rule exists to avoid.
  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    defer { Task { await persistCursor() } }
    return try await connectionService.syncNow()
  }

  public func startBackfill(months: Int) async throws {
    defer { Task { await persistCursor() } }
    try await connectionService.startBackfill(months: months)
  }

  public func connect(_ credentials: IMAPCredentials) async throws {
    try await connectionService.connect(credentials)
  }

  /// Restores the last session on launch, so a returning user is connected
  /// without retyping an app password. Silent by design: a missing credential
  /// is the ordinary "never connected" case, not an error to surface.
  public func reconnectFromKeychain(_ store: any MailCredentialStoring) async {
    // One `guard let`, not two. `load()` returns `IMAPCredentials?` and `try?`
    // flattens rather than nesting, so there is no second layer to unwrap —
    // "no credential stored" and "the keychain read failed" arrive as the same
    // nil, and both mean the same thing here: nothing to reconnect to.
    guard let credentials = try? store.load() else { return }
    try? await connectionService.connect(credentials)
  }

  private func persistCursor() async {
    let cursor = await engine.cursor
    preferences.set(try? JSONEncoder().encode(cursor), forKey: PreferenceKey.mailSyncCursor)
  }

  private static func loadCursor(from preferences: any KeyValueStoring) -> MailSyncCursor? {
    guard let data = preferences.data(forKey: PreferenceKey.mailSyncCursor) else { return nil }
    return try? JSONDecoder().decode(MailSyncCursor.self, from: data)
  }
}
