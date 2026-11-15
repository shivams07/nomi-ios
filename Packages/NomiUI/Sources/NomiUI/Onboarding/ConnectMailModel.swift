import Foundation
import NomiCore
import Observation

/// What one state change asks the Connect mail screen to do: start backfill when
/// the connection is made, and announce a failed attempt for VoiceOver.
struct ConnectMailObservation: Equatable {
  let becameConnected: Bool
  let announcement: String?
}

/// The Connect mail screen's state and actions, outside the view (T2a), so plain
/// XCTest can drive them with a spy service. The view owns one through `@State`.
/// Copy, layout and the offer rule are unchanged from `ConnectMailScreen`.
@Observable @MainActor final class ConnectMailModel {
  @ObservationIgnored let service: MailConnectionService

  private(set) var connectionState: MailConnectionState = .disconnected
  /// What this screen knows of the connection. The state stream carries
  /// `lastSync` only while connected, so these are what the attention card
  /// needs to say "Last synced …" after a disconnect. Seeded from the persisted
  /// history in `init`, so a relaunch does not start from "never connected".
  private(set) var hadConnection: Bool
  private(set) var lastKnownSync: Date?
  /// A password is saved on this device. Read in `init`, and again on every
  /// state change: connecting saves one, disconnecting deletes it, and a
  /// screen that outlives either would otherwise show a stale offer.
  private(set) var hasSaved: Bool
  private(set) var isConnecting = false
  private(set) var didAttemptOnce = false
  var errorMessage: String?
  var isConfirmingDisconnect = false
  /// Set by `requestDisconnect`, cleared by `cancelDisconnect` and by a confirmed
  /// disconnect. `confirmDisconnect` does nothing without it.
  @ObservationIgnored private var disconnectArmed = false

  init(service: MailConnectionService) {
    self.service = service
    // `history` is synchronous and already on disk; it is read before the state
    // loop in `.task` starts, so the first render carries the right card.
    let seed = MailAttentionSeed(history: service.history)
    hadConnection = seed.hadConnection
    lastKnownSync = seed.lastSync
    hasSaved = service.hasStoredCredential
  }

  /// The "Try again" offer, as the view shows it.
  var isReconnectOfferShown: Bool {
    ReconnectOffer.isShown(
      state: connectionState,
      hadConnection: hadConnection,
      hasStoredCredential: hasSaved
    )
  }

  /// The inline error line already says what failed on the last attempt, so the
  /// attention card stays out of its way.
  func attention(now: Date) -> MailAttentionCopy? {
    if didAttemptOnce, case .failed = connectionState { return nil }
    return MailAttentionLogic.copy(
      for: connectionState,
      hadConnection: hadConnection,
      lastSync: lastKnownSync,
      now: now
    )
  }

  var errorText: String? {
    guard didAttemptOnce, case .failed(let error) = connectionState else { return nil }
    return MailErrorMessage.text(for: error)
  }

  /// Applies one state from the stream. Returns what the view should do with it.
  func observe(_ state: MailConnectionState) -> ConnectMailObservation {
    connectionState = state
    hasSaved = service.hasStoredCredential
    var becameConnected = false
    if case .connected(_, let lastSync) = state {
      hadConnection = true
      if let lastSync { lastKnownSync = lastSync }
      becameConnected = true
    }
    // A failed attempt is announced here, not on appearance: the error line
    // is inserted with its text already set, which `onChange` would miss.
    var announcement: String?
    if didAttemptOnce, case .failed(let error) = state {
      announcement = MailErrorMessage.text(for: error)
    }
    return ConnectMailObservation(becameConnected: becameConnected, announcement: announcement)
  }

  @discardableResult
  func connect(_ credentials: IMAPCredentials) -> Task<Void, Never> {
    didAttemptOnce = true
    isConnecting = true
    // `try?` is deliberate: a failed connect already renders through
    // `connectionState`'s `.failed` case, so a second alert would repeat it.
    return Task {
      defer { isConnecting = false }
      try? await service.connect(credentials)
    }
  }

  /// Reconnects with the saved password. The thrown error is discarded on
  /// purpose: the failure reaches the screen as `.failed` on the state stream
  /// (I-3). The offer is re-read afterwards, so a rejected password that was
  /// deleted hides it.
  @discardableResult
  func tryAgain() -> Task<Void, Never> {
    didAttemptOnce = true
    isConnecting = true
    return Task {
      defer {
        isConnecting = false
        hasSaved = service.hasStoredCredential
      }
      try? await service.reconnectWithStoredCredential()
    }
  }

  @discardableResult
  func syncNow() -> Task<Void, Never> {
    Task {
      do {
        try await service.syncNow()
      } catch {
        errorMessage = "Couldn't sync right now. Try again in a moment."
      }
    }
  }

  /// Arms the disconnect. It calls no service method: the confirmation dialog
  /// decides whether `confirmDisconnect` runs.
  func requestDisconnect() {
    disconnectArmed = true
    isConfirmingDisconnect = true
  }

  func cancelDisconnect() {
    disconnectArmed = false
  }

  /// Disconnects only after `requestDisconnect`. Returns nil and does nothing
  /// otherwise.
  @discardableResult
  func confirmDisconnect() -> Task<Void, Never>? {
    guard disconnectArmed else { return nil }
    disconnectArmed = false
    return Task {
      do {
        try await service.disconnect()
      } catch {
        errorMessage = "Couldn't disconnect right now. Try again in a moment."
      }
    }
  }
}
