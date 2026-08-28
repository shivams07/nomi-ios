import Foundation
import NomiCore

/// Preview-only `MailConnectionService` fakes that hold a single fixed state
/// for the whole preview lifetime. `NomiPreview.FakeMailConnectionService`
/// only ever transitions live (connecting -> connected on `connect()`), which
/// cannot render a static "already connected" or "already failed" canvas —
/// these exist here, in `Onboarding/**`, because this unit must not edit
/// `NomiPreview` (owned by U1).
actor ConnectedFakeMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  init() {
    state = AsyncStream { continuation in
      continuation.yield(.connected(address: "shivam@example.com", lastSync: Date(timeIntervalSinceNow: -300)))
    }
    backfillProgress = AsyncStream { _ in }
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  @discardableResult func syncNow() async throws -> SyncSummary {
    SyncSummary(scanned: 12, created: 3, merged: 1, flagged: 1, packMatched: 3, heuristicMatched: 1, unmatchedSenders: [])
  }
  func startBackfill(months: Int) async throws {}
}

actor FailedFakeMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  init() {
    state = AsyncStream { continuation in
      continuation.yield(.failed(.authenticationFailed))
    }
    backfillProgress = AsyncStream { _ in }
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  @discardableResult func syncNow() async throws -> SyncSummary {
    SyncSummary(scanned: 0, created: 0, merged: 0, flagged: 0, packMatched: 0, heuristicMatched: 0, unmatchedSenders: [])
  }
  func startBackfill(months: Int) async throws {}
}

actor ConnectingFakeMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  init() {
    state = AsyncStream { continuation in
      continuation.yield(.connecting)
    }
    backfillProgress = AsyncStream { _ in }
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  @discardableResult func syncNow() async throws -> SyncSummary {
    SyncSummary(scanned: 0, created: 0, merged: 0, flagged: 0, packMatched: 0, heuristicMatched: 0, unmatchedSenders: [])
  }
  func startBackfill(months: Int) async throws {}
}

/// A `BackfillProgress` stream fixed at a single point, for the hero screen's
/// mid-scan / complete previews — same "static fake" reasoning as above.
actor FixedBackfillFakeMailConnectionService: MailConnectionService {
  nonisolated let state: AsyncStream<MailConnectionState>
  nonisolated let backfillProgress: AsyncStream<BackfillProgress>

  init(progress: BackfillProgress) {
    state = AsyncStream { continuation in
      continuation.yield(.connected(address: "shivam@example.com", lastSync: Date()))
    }
    backfillProgress = AsyncStream { continuation in
      continuation.yield(progress)
    }
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  @discardableResult func syncNow() async throws -> SyncSummary {
    SyncSummary(scanned: 1200, created: 58, merged: 4, flagged: 6, packMatched: 44, heuristicMatched: 14, unmatchedSenders: [])
  }
  func startBackfill(months: Int) async throws {}
}
