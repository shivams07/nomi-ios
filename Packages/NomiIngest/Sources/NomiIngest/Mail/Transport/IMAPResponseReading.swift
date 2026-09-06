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
  /// `* BYE` (or a closed stream) arrived before the tagged completion of a
  /// command. Distinct from `connectionClosed`, which is an orderly shutdown:
  /// this one means a batch is short and must NOT be treated as complete
  /// (§2.16). `MailFetching.fetch` throws it; `MailSyncEngine` then leaves the
  /// cursor alone and the UIDs are re-fetched next sync.
  case serverClosedMidCommand(tag: String, text: String)
  case notConnected
  case authenticationFailed(String)
  case commandFailed(tag: String, status: IMAPCompletionStatus, text: String)
  case malformedResponse(String)
  case connectionClosed

  /// The credential could not be put on the wire at all, so nothing was sent
  /// and no socket was opened (B6).
  ///
  /// IMAP commands are CRLF-terminated, and a quoted-string cannot contain a
  /// bare CR or LF (RFC 3501). `IMAPCommand.quoted` escapes `\` and `"` and
  /// nothing else, because those are the only escapes the grammar has - a
  /// newline pasted into the password field would end the LOGIN line early and
  /// hand the remainder to the server as a fresh command. Users paste Google
  /// app passwords out of a web page, so this is an ordinary accident rather
  /// than an attack, and either way it is caught here.
  case invalidCredentials(String)
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
