import Foundation

/// Turns the stream of `IMAPServerEvent`s produced by one `UID FETCH` into
/// either its messages or an error. Pure: no socket, no clock, no I/O.
///
/// This is where "a hangup must not look like an empty sync" is actually
/// enforced (design §2.16). `.connectionClosing` is *reported* rather than
/// thrown by the reader, because `* BYE` is routine on LOGOUT and on an idle
/// timeout and throwing there would make ordinary disconnection indistinguishable
/// from failure. But a `* BYE` arriving **before the tagged completion of a
/// FETCH** is not routine: it means the server cut us off partway through, and
/// the messages that happened to arrive are not the messages that exist.
///
/// Returning them would hand `MailSyncEngine` a short batch it would treat as a
/// complete one — advancing the cursor past UIDs that were never fetched, which
/// is data loss that never surfaces. Throwing instead leaves the cursor where it
/// was; the same UIDs are re-fetched next sync and the pipeline absorbs the
/// repeat as a no-op.
public struct IMAPFetchSequencer {
  /// One fetched message, still raw. `RFC822Message.parse` is the only thing
  /// that should look inside `bytes`.
  public struct Fetched: Equatable, Sendable {
    public let uid: UInt32
    public let bytes: [UInt8]

    public init(uid: UInt32, bytes: [UInt8]) {
      self.uid = uid
      self.bytes = bytes
    }
  }

  private let tag: String
  private var fetched: [Fetched] = []
  private var isComplete = false

  public init(tag: String) {
    self.tag = tag
  }

  /// Feeds one event.
  ///
  /// - Returns: `true` once the tagged completion for this command has arrived,
  ///   after which `messages` is final.
  /// - Throws: if the server closed mid-fetch, or completed the command with
  ///   `NO` / `BAD`.
  @discardableResult
  public mutating func apply(_ event: IMAPServerEvent) throws -> Bool {
    switch event {
    case .fetchedMessage(let uid, let bytes):
      fetched.append(Fetched(uid: uid, bytes: bytes))
      return false

    case .connectionClosing(let text):
      // Before the tagged completion, so: not routine.
      throw IMAPTransportError.serverClosedMidCommand(tag: tag, text: text)

    case .commandCompleted(let completedTag, let status, let text):
      // Untagged chatter and completions for other commands are not ours.
      guard completedTag == tag else { return false }
      switch status {
      case .ok:
        isComplete = true
        return true
      case .no, .bad:
        throw IMAPTransportError.commandFailed(tag: tag, status: status, text: text)
      }

    case .uidValidity, .uidNext, .searchResults, .continuationRequest:
      return false
    }
  }

  /// Feeds a batch, stopping at the tagged completion.
  @discardableResult
  public mutating func apply(_ events: [IMAPServerEvent]) throws -> Bool {
    for event in events where !isComplete {
      if try apply(event) { return true }
    }
    return isComplete
  }

  /// The messages, but **only** once the command completed successfully.
  ///
  /// A stream that ended without a tagged completion — socket closed, read
  /// timed out — is the same failure as a mid-fetch `* BYE` and gets the same
  /// treatment. Callers cannot reach a partial batch by accident because there
  /// is no accessor that returns one.
  public func messages() throws -> [Fetched] {
    guard isComplete else {
      throw IMAPTransportError.serverClosedMidCommand(
        tag: tag, text: "stream ended before the tagged completion")
    }
    return fetched
  }

  /// How many have arrived so far. For progress reporting only — deliberately
  /// not a way to get at the payload before the command completed.
  public var receivedCount: Int { fetched.count }
}
