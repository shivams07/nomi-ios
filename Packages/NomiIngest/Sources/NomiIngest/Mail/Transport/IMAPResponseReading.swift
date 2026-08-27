import Foundation

/// The only IMAP responses this client has to understand, because it only ever
/// issues five commands.
public enum IMAPServerEvent: Equatable, Sendable {
  /// `* OK [UIDVALIDITY 900100]`
  case uidValidity(UInt32)
  /// `* OK [UIDNEXT 4392]`
  case uidNext(UInt32)
  /// `* SEARCH 12 13 14`
  case searchResults([UInt32])
  /// One complete `UID FETCH … BODY.PEEK[]` message: its UID and its raw RFC
  /// 5322 bytes, handed to `RFC822Message.parse` and nothing else.
  case fetchedMessage(uid: UInt32, bytes: [UInt8])
  /// `+ idling` — the server accepted IDLE, or is asking for a literal.
  case continuationRequest
  /// `a001 OK …` / `a001 NO …` / `a001 BAD …`
  case commandCompleted(tag: String, status: IMAPCompletionStatus, text: String)
  /// `* BYE …` — the server is closing the connection.
  ///
  /// Surfaced rather than thrown. swift-nio-imap can report this as either
  /// `Response.fatal` or an untagged `.bye` depending on where in the session it
  /// arrives, and a reader that threw on one shape and ignored the other would
  /// behave differently for the same wire bytes. Both map here; deciding what to
  /// do about a closing connection is the transport's job, not the parser's.
  case connectionClosing(text: String)
}

public enum IMAPCompletionStatus: String, Equatable, Sendable {
  case ok, no, bad
}

public enum IMAPTransportError: Error, Sendable, Equatable {
  case notConnected
  case authenticationFailed(String)
  case commandFailed(tag: String, status: IMAPCompletionStatus, text: String)
  case malformedResponse(String)
  case connectionClosed
}

/// Turns raw server bytes into `IMAPServerEvent`s, incrementally, across packet
/// boundaries.
///
/// The seam exists so the byte-level parsing can be swapped without disturbing
/// anything above it. `NIOIMAPResponseReader` is the implementation;
/// `RecordedTranscriptReader`-style test doubles are the other users.
public protocol IMAPResponseReading: AnyObject, Sendable {
  /// Feed bytes as they arrive. Returns every complete event they contained;
  /// partial responses are buffered until the rest arrives.
  func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent]
  /// Discard buffered state — a new connection starts clean.
  func reset()
}
