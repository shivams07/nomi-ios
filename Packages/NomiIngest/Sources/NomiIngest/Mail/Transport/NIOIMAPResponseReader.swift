import Foundation
import NIOCore

// `FramingParser`'s type is public, but its `init` and `appendAndFrameBuffer`
// are `@_spi(NIOIMAPInternal)`, so reaching them needs an SPI import rather than
// a plain one. `ResponseParser` needs no SPI — it is plainly public, and it
// arrives through `NIOIMAP`'s single-line `@_exported import NIOIMAPCore`.
@_spi(NIOIMAPInternal) import NIOIMAP

/// Turns raw server bytes into `IMAPServerEvent`s using swift-nio-imap.
///
/// Two stages, per design §2.15:
///
/// 1. **`FramingParser`** splits the byte stream into frames. This is the part
///    worth borrowing rather than writing: IMAP literals are `{123}` followed by
///    exactly 123 octets which may themselves contain CRLF and must not be
///    line-split — and a `FETCH BODY.PEEK[]` response is made of precisely that.
///    A hand-rolled line splitter gets this wrong on the first email containing
///    a blank line, which is all of them.
/// 2. **`ResponseParser`** parses each frame into a `ResponseOrContinuationRequest`.
///    Fed in a loop until it returns `nil`; no
///    `NIOSingleStepByteToMessageProcessor` is involved.
///
/// `NIOCore` is linked for exactly one reason: naming `ByteBuffer` here (§2.15).
public final class NIOIMAPResponseReader: IMAPResponseReading, @unchecked Sendable {
  /// **Not the library defaults, and the difference matters.**
  ///
  /// `ResponseParser.Options` defaults `literalSizeLimit` to
  /// `IMAPDefaults.literalSizeLimit` — 4096 bytes — and `bufferLimit` to 8192.
  /// A single HTML bank alert is routinely larger than either. Left at the
  /// defaults this reader would throw on ordinary mail, and it would do so on
  /// the *biggest* messages, which is the opposite of the failure you would
  /// notice in a fixture.
  ///
  /// `bodySizeLimit` is a real ceiling rather than a formality: it bounds what a
  /// hostile or broken server can make the app allocate for one message.
  public struct Limits: Sendable {
    public var literalSizeLimit: Int
    public var bufferLimit: Int
    public var bodySizeLimit: UInt64
    public var framingBufferLimit: Int

    public init(
      literalSizeLimit: Int = 8 * 1024 * 1024,
      bufferLimit: Int = 1024 * 1024,
      bodySizeLimit: UInt64 = 25 * 1024 * 1024,
      framingBufferLimit: Int = 8 * 1024 * 1024
    ) {
      self.literalSizeLimit = literalSizeLimit
      self.bufferLimit = bufferLimit
      self.bodySizeLimit = bodySizeLimit
      self.framingBufferLimit = framingBufferLimit
    }
  }

  private let limits: Limits
  private let lock = NSLock()

  private var framing: FramingParser
  private var parser: ResponseParser

  /// Assembly state for the FETCH currently in flight. A FETCH arrives as
  /// several events — start, attributes, streamed body, finish — and only the
  /// `finish` knows the message is whole.
  private var pendingUID: UInt32?
  private var pendingBody: [UInt8] = []

  public init(limits: Limits = Limits()) {
    self.limits = limits
    self.framing = FramingParser(bufferSizeLimit: limits.framingBufferLimit)
    self.parser = ResponseParser(
      options: ResponseParser.Options(
        bufferLimit: limits.bufferLimit,
        bodySizeLimit: limits.bodySizeLimit,
        literalSizeLimit: limits.literalSizeLimit
      )
    )
  }

  public func reset() {
    lock.lock()
    defer { lock.unlock() }
    framing = FramingParser(bufferSizeLimit: limits.framingBufferLimit)
    parser = ResponseParser(
      options: ResponseParser.Options(
        bufferLimit: limits.bufferLimit,
        bodySizeLimit: limits.bodySizeLimit,
        literalSizeLimit: limits.literalSizeLimit
      )
    )
    pendingUID = nil
    pendingBody = []
  }

  public func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent] {
    lock.lock()
    defer { lock.unlock() }

    var incoming = ByteBuffer(bytes: bytes)
    let frames: [FramingResult]
    do {
      frames = try framing.appendAndFrameBuffer(&incoming)
    } catch {
      throw IMAPTransportError.malformedResponse(String(describing: error))
    }

    var events: [IMAPServerEvent] = []
    for frame in frames {
      switch frame {
      case .complete(var buffer), .insideLiteral(var buffer, _):
        try events.append(contentsOf: parse(&buffer))
      case .incomplete:
        // More bytes needed. Nothing to report, and nothing is lost — the
        // framing parser keeps the partial frame.
        continue
      case .invalid(let buffer):
        throw IMAPTransportError.malformedResponse(
          "unparseable frame: \(String(decoding: buffer.readableBytesView, as: UTF8.self))")
      }
    }
    return events
  }

  // MARK: -

  private func parse(_ buffer: inout ByteBuffer) throws -> [IMAPServerEvent] {
    var events: [IMAPServerEvent] = []

    while buffer.readableBytes > 0 {
      let before = buffer.readableBytes
      let parsed: ResponseOrContinuationRequest?
      do {
        parsed = try parser.parseResponseStream(buffer: &buffer)
      } catch {
        throw IMAPTransportError.malformedResponse(String(describing: error))
      }

      guard let parsed else {
        // Needs more bytes. Guard against a parser that consumed nothing —
        // without this an unconsumable frame would spin this loop forever, on a
        // background sync, with no way for the user to tell.
        break
      }
      if let event = map(parsed) {
        events.append(event)
      }
      if buffer.readableBytes == before { break }
    }
    return events
  }

  private func map(_ parsed: ResponseOrContinuationRequest) -> IMAPServerEvent? {
    switch parsed {
    case .continuationRequest:
      return .continuationRequest

    case .response(let response):
      return map(response)
    }
  }

  private func map(_ response: Response) -> IMAPServerEvent? {
    switch response {
    case .tagged(let tagged):
      switch tagged.state {
      case .ok(let text):
        return .commandCompleted(tag: tagged.tag, status: .ok, text: text.text)
      case .no(let text):
        return .commandCompleted(tag: tagged.tag, status: .no, text: text.text)
      case .bad(let text):
        return .commandCompleted(tag: tagged.tag, status: .bad, text: text.text)
      }

    case .untagged(let payload):
      return mapUntagged(payload)

    case .fetch(let fetch):
      return mapFetch(fetch)

    case .fatal(let text):
      return .connectionClosing(text: text.text)

    case .idleStarted:
      // The server accepted IDLE. Same signal to the caller as a `+`.
      return .continuationRequest

    case .authenticationChallenge:
      // We authenticate with LOGIN, never AUTHENTICATE, so this cannot arise
      // from a command this client issues.
      return nil
    }
  }

  private func mapUntagged(_ payload: ResponsePayload) -> IMAPServerEvent? {
    switch payload {
    case .mailboxData(.search(let identifiers, _)):
      // `UnknownMessageIdentifier` -> `UID` uses the public conversion init;
      // `UID.rawValue` is public, `UIDValidity.rawValue` is not (hence the
      // `UInt32(...)` conversion below).
      return .searchResults(identifiers.map { UID($0).rawValue })

    case .conditionalState(.bye(let text)):
      return .connectionClosing(text: text.text)

    case .conditionalState(.ok(let text)):
      switch text.code {
      case .uidValidity(let validity):
        return .uidValidity(UInt32(validity))
      case .uidNext(let uid):
        return .uidNext(uid.rawValue)
      default:
        return nil
      }

    default:
      return nil
    }
  }

  private func mapFetch(_ fetch: FetchResponse) -> IMAPServerEvent? {
    switch fetch {
    case .start:
      pendingUID = nil
      pendingBody = []
      return nil

    case .startUID(let uid):
      // RFC 9586 UID-only mode. We do not ask for it, but a server may use it.
      pendingUID = uid.rawValue
      pendingBody = []
      return nil

    case .simpleAttribute(.uid(let uid)):
      pendingUID = uid.rawValue
      return nil

    case .streamingBegin(_, let byteCount):
      pendingBody.reserveCapacity(byteCount)
      return nil

    case .streamingBytes(let buffer):
      pendingBody.append(contentsOf: buffer.readableBytesView)
      return nil

    case .streamingEnd, .simpleAttribute:
      return nil

    case .finish:
      defer {
        pendingUID = nil
        pendingBody = []
      }
      // No UID means we cannot build a `SourceRef`, so the message is dropped
      // rather than ingested under a fabricated identity — a wrong externalID
      // would break re-ingest idempotence silently.
      guard let uid = pendingUID, !pendingBody.isEmpty else { return nil }
      return .fetchedMessage(uid: uid, bytes: pendingBody)
    }
  }
}
