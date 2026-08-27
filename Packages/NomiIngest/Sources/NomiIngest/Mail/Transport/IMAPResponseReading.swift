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
  /// Raised by `UnimplementedResponseReader`. See its doc comment — this is a
  /// blocked design decision surfacing at runtime, not a bug to work around.
  case responseParsingUnavailable
}

/// Turns raw server bytes into `IMAPServerEvent`s, incrementally, across packet
/// boundaries.
///
/// **This protocol has no working implementation yet, and that is an escalation
/// rather than an omission.** Design §2.14 specified driving `NIOIMAP`'s
/// encoder/decoder over an `NWConnection` byte stream via
/// `NIOSingleStepByteToMessageProcessor`. Checked against swift-nio-imap 0.4.0,
/// that specific route cannot be built from outside the `NIOIMAP` module:
///
/// - `ResponseDecoder` is `internal`. It cannot be constructed by a caller.
/// - `CommandEncoder` is `internal`, and `CommandEncodeBuffer.writeCommandStream`
///   is `@_spi(NIOIMAPInternal)`. (Harmless — `IMAPCommand` writes the command
///   text directly and is tested byte-for-byte.)
/// - `NIOSingleStepByteToMessageProcessor` lives in `NIOCore`, which
///   `NomiIngest/Package.swift` does not declare.
/// - `IMAPClientHandler` *is* public, but it is a `ChannelDuplexHandler` and
///   needs a full NIO `ChannelPipeline` and `EventLoopGroup` — which is the
///   channel route §2.14 rejected for needing `swift-nio-ssl` and
///   `swift-nio-transport-services`.
///
/// What *is* usable: `NIOIMAPCore.ResponseParser` is `public`, `Sendable`, and
/// exposes `public mutating func parseResponseStream(buffer: inout ByteBuffer)
/// throws -> ResponseOrContinuationRequest?`. It is exactly the right tool and
/// needs no channel. Its one requirement is that `ByteBuffer` be nameable here,
/// which means `import NIOCore` — a package the manifest does not declare.
///
/// §2.10 forbids a dependency change and §2.14 makes it an escalation to the
/// architect, not a judgement call, so the decision is his. The seam is here so
/// that whichever way it goes, only the conformer below changes.
public protocol IMAPResponseReading: AnyObject, Sendable {
  /// Feed bytes as they arrive. Returns every complete event they contained;
  /// partial responses are buffered until the rest arrives.
  func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent]
  /// Discard buffered state — a new connection starts clean.
  func reset()
}

/// The placeholder that keeps the unit compiling and honest.
///
/// It parses nothing and says so. `IMAPMailConnectionService` will surface
/// `responseParsingUnavailable` rather than pretend a sync succeeded, because a
/// mail client that silently reports "0 new transactions" is worse than one that
/// reports an error.
public final class UnimplementedResponseReader: IMAPResponseReading {
  public init() {}

  public func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent] {
    throw IMAPTransportError.responseParsingUnavailable
  }

  public func reset() {}
}
