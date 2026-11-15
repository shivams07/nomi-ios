import Foundation
import NomiCore

/// A `MailConnectionService` that records every call and never yields a state on its
/// own. A test emits states with `emit(_:)`, so a test decides what the screen sees.
/// Every mutable field is behind one lock, so the spy is safe to call from any task.
final class MailConnectionSpy: MailConnectionService, @unchecked Sendable {
  enum Call: Equatable {
    case connect, reconnect, disconnect, syncNow, startBackfill(months: Int)
  }

  let state: AsyncStream<MailConnectionState>
  let backfillProgress: AsyncStream<BackfillProgress> = AsyncStream { _ in }
  let history: MailConnectionHistory

  private let continuation: AsyncStream<MailConnectionState>.Continuation
  private let lock = NSLock()
  private var recordedCalls: [Call] = []
  private var failures: [(call: Call, error: Error)] = []
  private var storedCredential: Bool
  private var deletesCredentialOnReconnect = false

  init(
    history: MailConnectionHistory = MailConnectionHistory(hasEverConnected: true, lastSync: nil),
    hasStoredCredential: Bool = true
  ) {
    let (stream, continuation) = AsyncStream.makeStream(of: MailConnectionState.self)
    state = stream
    self.continuation = continuation
    self.history = history
    storedCredential = hasStoredCredential
  }

  var hasStoredCredential: Bool {
    lock.lock()
    defer { lock.unlock() }
    return storedCredential
  }

  func setStoredCredential(_ value: Bool) {
    lock.lock()
    defer { lock.unlock() }
    storedCredential = value
  }

  /// The calls made so far, in call order.
  var calls: [Call] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCalls
  }

  /// `call` throws `error` after it is recorded.
  func fail(_ call: Call, with error: Error) {
    lock.lock()
    defer { lock.unlock() }
    failures.append((call: call, error: error))
  }

  /// When true, `reconnectWithStoredCredential` clears the saved password before it
  /// throws or returns, as a rejected password does on the device.
  var reconnectDeletesCredential: Bool {
    get {
      lock.lock()
      defer { lock.unlock() }
      return deletesCredentialOnReconnect
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      deletesCredentialOnReconnect = newValue
    }
  }

  func emit(_ state: MailConnectionState) {
    continuation.yield(state)
  }

  func connect(_ credentials: IMAPCredentials) async throws {
    try record(.connect)
  }

  func disconnect() async throws {
    try record(.disconnect)
  }

  @discardableResult
  func syncNow() async throws -> SyncSummary {
    try record(.syncNow)
    return Self.summary
  }

  @discardableResult
  func startBackfill(months: Int) async throws -> SyncSummary {
    try record(.startBackfill(months: months))
    return Self.summary
  }

  func reconnectWithStoredCredential() async throws {
    if deletesCredentialOnReconnectNow() { setStoredCredential(false) }
    try record(.reconnect)
  }

  private func deletesCredentialOnReconnectNow() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return deletesCredentialOnReconnect
  }

  private static let summary = SyncSummary(
    scanned: 3,
    created: 2,
    merged: 0,
    flagged: 0,
    packMatched: 2,
    heuristicMatched: 0,
    unmatchedSenders: []
  )

  /// Records `call`, then throws the error configured for it, if any.
  private func record(_ call: Call) throws {
    lock.lock()
    recordedCalls.append(call)
    let failure = failures.first { $0.call == call }?.error
    lock.unlock()
    if let failure { throw failure }
  }
}
