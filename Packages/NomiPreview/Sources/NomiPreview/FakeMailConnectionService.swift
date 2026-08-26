import Foundation
import NomiCore

public actor FakeMailConnectionService: MailConnectionService {
  private var stateContinuation: AsyncStream<MailConnectionState>.Continuation?
  private var backfillContinuation: AsyncStream<BackfillProgress>.Continuation?

  public nonisolated let state: AsyncStream<MailConnectionState>
  public nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  public init() {
    var stateContinuation: AsyncStream<MailConnectionState>.Continuation!
    self.state = AsyncStream { stateContinuation = $0 }
    var backfillContinuation: AsyncStream<BackfillProgress>.Continuation!
    self.backfillProgress = AsyncStream { backfillContinuation = $0 }
    self.stateContinuation = stateContinuation
    self.backfillContinuation = backfillContinuation
  }

  public func connect(_ credentials: IMAPCredentials) async throws {
    stateContinuation?.yield(.connecting)
    stateContinuation?.yield(.connected(address: credentials.address, lastSync: Date()))
  }

  public func disconnect() async throws {
    stateContinuation?.yield(.disconnected)
  }

  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    SyncSummary(scanned: 12, created: 3, merged: 1, flagged: 1, packMatched: 3, heuristicMatched: 1, unmatchedSenders: [])
  }

  public func startBackfill(months: Int) async throws {
    let total = months * 30
    backfillContinuation?.yield(BackfillProgress(scanned: total, total: total, created: 0))
  }
}
