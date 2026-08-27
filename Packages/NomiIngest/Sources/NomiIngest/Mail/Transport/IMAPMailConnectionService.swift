import Foundation
import NomiCore

/// The `MailConnectionService` U8 wires, composed over U2's `MailSyncEngine`
/// and whatever implements `MailFetching`.
///
/// U8's composition root talks to this and nothing below it. It is deliberately
/// transport-agnostic: it holds no socket, speaks no IMAP, and would work
/// unchanged against a Gmail API implementation of `MailFetching` if that ever
/// arrives (§1.1).
public final class IMAPMailConnectionService: MailConnectionService, @unchecked Sendable {
  private let fetcher: any MailFetching
  private let engine: MailSyncEngine
  private let credentials: any MailCredentialStoring
  private let now: @Sendable () -> Date

  // `AsyncStream` is single-consumer by construction. U8 consumes each of these
  // exactly once, at the composition root; a second `for await` over the same
  // stream would compete for elements rather than mirror them.
  public let state: AsyncStream<MailConnectionState>
  public let backfillProgress: AsyncStream<BackfillProgress>

  private let stateContinuation: AsyncStream<MailConnectionState>.Continuation
  private let progressContinuation: AsyncStream<BackfillProgress>.Continuation

  private let lock = NSLock()
  private var connectedAddress: String?
  private var lastSync: Date?

  public init(
    fetcher: any MailFetching,
    engine: MailSyncEngine,
    credentials: any MailCredentialStoring,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.fetcher = fetcher
    self.engine = engine
    self.credentials = credentials
    self.now = now

    // Unbounded, so no transition is ever dropped. The obvious alternative —
    // `.bufferingNewest(1)`, "a late consumer only wants the current state" —
    // loses `.connecting` whenever a connect completes faster than the UI
    // attaches, which is most of the time, and a spinner that never appears is
    // indistinguishable from one that never goes away. There are a handful of
    // these values per session, so the buffer costs nothing.
    var stateContinuation: AsyncStream<MailConnectionState>.Continuation!
    self.state = AsyncStream(bufferingPolicy: .unbounded) { stateContinuation = $0 }
    self.stateContinuation = stateContinuation

    var progressContinuation: AsyncStream<BackfillProgress>.Continuation!
    self.backfillProgress = AsyncStream(bufferingPolicy: .unbounded) {
      progressContinuation = $0
    }
    self.progressContinuation = progressContinuation

    stateContinuation.yield(.disconnected)
  }

  deinit {
    stateContinuation.finish()
    progressContinuation.finish()
  }

  // MARK: - Connect

  /// Saves the credential, then connects. In that order, deliberately.
  ///
  /// A credential that connects once and is not persisted leaves the user
  /// "connected" until the app is killed and silently disconnected afterwards.
  /// If the connection then fails, the credential is removed again — storing a
  /// password that was just rejected only produces a background sync that fails
  /// forever without telling anyone.
  public func connect(_ credentials: IMAPCredentials) async throws {
    stateContinuation.yield(.connecting)

    do {
      try self.credentials.save(credentials)
      try await fetcher.connect(credentials)
    } catch {
      try? self.credentials.delete()
      setConnected(nil)
      stateContinuation.yield(.failed(mailError(from: error)))
      throw error
    }

    setConnected(credentials.address)
    stateContinuation.yield(.connected(address: credentials.address, lastSync: currentLastSync()))
  }

  /// Stops capture. **Deletes no transactions** — that is the acceptance
  /// criterion and it is the whole point: a user disconnecting a mailbox is
  /// turning off collection, not asking for their ledger to be erased.
  ///
  /// It does remove the stored password, because leaving a live mailbox
  /// credential in the Keychain for an account the user just disconnected is not
  /// what "disconnect" means to anyone.
  public func disconnect() async throws {
    defer {
      setConnected(nil)
      stateContinuation.yield(.disconnected)
    }
    try await fetcher.disconnect()
    try credentials.delete()
  }

  // MARK: - Sync

  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    let address = try requireConnectedAddress()

    do {
      let summary = try await engine.syncNow()
      recordSync(at: now())
      stateContinuation.yield(.connected(address: address, lastSync: currentLastSync()))
      return summary
    } catch {
      stateContinuation.yield(.failed(mailError(from: error)))
      throw error
    }
  }

  /// Six months at first run (§1.3). This is also the run that produces
  /// `unmatchedSenders` — the measurement that tells us which banks the user
  /// actually has, computed on their own device (§2.5.1).
  ///
  /// Progress is the engine's, forwarded verbatim: one tick per completed batch
  /// of 50 (§2.17). This service adds nothing to it and must not — a count
  /// synthesised here would be a second opinion about work it did not do.
  ///
  /// The one tick it does emit is the leading `total: 0`, before the engine has
  /// finished its windowed search and knows how many messages there are.
  /// `BackfillBanner` reads a zero total as an empty bar rather than dividing by
  /// it, which is the honest rendering of "still looking".
  public func startBackfill(months: Int) async throws {
    let address = try requireConnectedAddress()
    progressContinuation.yield(BackfillProgress(scanned: 0, total: 0, created: 0))

    do {
      let continuation = progressContinuation
      _ = try await engine.backfill(months: months) { tick in
        continuation.yield(tick)
      }
      recordSync(at: now())
      stateContinuation.yield(.connected(address: address, lastSync: currentLastSync()))
    } catch {
      stateContinuation.yield(.failed(mailError(from: error)))
      throw error
    }
  }

  // MARK: -

  private func requireConnectedAddress() throws -> String {
    lock.lock()
    defer { lock.unlock() }
    guard let connectedAddress else { throw IMAPTransportError.notConnected }
    return connectedAddress
  }

  private func setConnected(_ address: String?) {
    lock.lock()
    connectedAddress = address
    lock.unlock()
  }

  private func recordSync(at date: Date) {
    lock.lock()
    lastSync = date
    lock.unlock()
  }

  private func currentLastSync() -> Date? {
    lock.lock()
    defer { lock.unlock() }
    return lastSync
  }

  /// `MailConnectionState.failed` carries a `MailError`, which has three cases.
  /// Anything unrecognised keeps its description rather than being flattened to
  /// `.connectionFailed` — the Settings screen showing the real reason is worth
  /// more than a tidy enum.
  private func mailError(from error: Error) -> MailError {
    if let mailError = error as? MailError { return mailError }
    if let transportError = error as? IMAPTransportError {
      switch transportError {
      case .authenticationFailed:
        return .authenticationFailed
      case .notConnected, .connectionClosed, .serverClosedMidCommand:
        return .connectionFailed
      case .commandFailed, .malformedResponse:
        return .unknown(String(describing: transportError))
      }
    }
    return .unknown(String(describing: error))
  }
}
