import Foundation
import NIOCore
import NIOIMAP

/// Turns raw server bytes into `IMAPServerEvent`s using swift-nio-imap.
///
/// Two stages (design §2.15):
///
/// 1. **`IMAPFraming`** splits the byte stream into frames — the literal-aware
///    part, wrapped in its own file because it needs SPI (§2.16).
/// 2. **`ResponseParser`** parses each frame, fed in a loop until it returns
///    `nil`. Plainly public, reached through `NIOIMAP`'s single-line
///    `@_exported import NIOIMAPCore`; no SPI and no
///    `NIOSingleStepByteToMessageProcessor`.
///
/// **Both `.complete` and `.literalChunk` frames go to the parser.** A reader
/// that handled only `.complete` would silently drop every message body large
/// enough to arrive as a literal, which is all of them. Reassembly happens via
/// the parser's `.streamingBytes` events accumulating into `pendingBody` — the
/// parser tracks the literal's remaining byte count itself, so there is no
/// second copy of that arithmetic here.
///
/// `NIOCore` is linked for exactly one reason: naming `ByteBuffer` (§2.15).
public final class NIOIMAPResponseReader: IMAPResponseReading, @unchecked Sendable {
  /// **What these actually do at swift-nio-imap 0.4.0, checked rather than
  /// assumed — and it is not what the field names suggest.**
  ///
  /// - `bodySizeLimit` — **enforced**, in `ResponseParser.guardStreamingSizeLimit`,
  ///   and it defaults to `UInt64.max`. The value below is therefore a
  ///   deliberate **tightening**, not a bug fix: it bounds what a hostile or
  ///   broken server can make the app allocate for one message. Do not "restore
  ///   the default" thinking something was broken.
  /// - `literalSizeLimit` — enforced, but **not on the message body**. It
  ///   reaches `GrammarParser(literalSizeLimit:)` and gates literals like
  ///   mailbox names and envelope fields. The FETCH body is sized against
  ///   `GrammarParser.messageBodySizeLimit`, which `ResponseParser.Options`
  ///   cannot set and which defaults to `.max`. So the library's 4096 default
  ///   does *not* reject a large email; raising it is headroom for an unusual
  ///   non-body literal and nothing more.
  /// - `bufferLimit` — **stored and never read** anywhere in `ResponseParser` at
  ///   0.4.0. It enforces nothing today. Passed anyway so the value is sane if
  ///   upstream starts honouring it.
  /// - `framingBufferLimit` — the framer's, not the parser's, and the only one
  ///   of the four that a real mailbox reaches. Derivation on
  ///   `IMAPFraming.defaultBufferSizeLimit` (§2.17).
  public struct Limits: Sendable {
    public var bodySizeLimit: UInt64
    public var literalSizeLimit: Int
    public var bufferLimit: Int
    public var framingBufferLimit: Int

    public init(
      bodySizeLimit: UInt64 = 25 * 1024 * 1024,
      literalSizeLimit: Int = 1024 * 1024,
      bufferLimit: Int = 1024 * 1024,
      framingBufferLimit: Int = IMAPFraming.defaultBufferSizeLimit
    ) {
      self.bodySizeLimit = bodySizeLimit
      self.literalSizeLimit = literalSizeLimit
      self.bufferLimit = bufferLimit
      self.framingBufferLimit = framingBufferLimit
    }

    /// The library's own defaults, for the tests that show what changing them
    /// does. Not for shipping.
    public static let libraryDefaults = Limits(
      bodySizeLimit: .max,
      literalSizeLimit: 4_096,
      bufferLimit: 8_192,
      framingBufferLimit: 8_192
    )
  }

  private let limits: Limits
  private let lock = NSLock()

  private var framing: IMAPFraming
  private var parser: ResponseParser

  /// Assembly state for the FETCH currently in flight. A FETCH arrives as
  /// several events — start, attributes, streamed body, finish — and only the
  /// `finish` knows the message is whole.
  private var pendingUID: UInt32?
  private var pendingBody: [UInt8] = []

  public init(limits: Limits = Limits()) {
    self.limits = limits
    self.framing = IMAPFraming(bufferSizeLimit: limits.framingBufferLimit)
    self.parser = Self.makeParser(limits)
  }

  private static func makeParser(_ limits: Limits) -> ResponseParser {
    ResponseParser(
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
    framing = IMAPFraming(bufferSizeLimit: limits.framingBufferLimit)
    parser = Self.makeParser(limits)
    pendingUID = nil
    pendingBody = []
  }

  public func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent] {
    lock.lock()
    defer { lock.unlock() }

    var incoming = ByteBuffer(bytes: bytes)
    let frames: [IMAPFrame]
    do {
      frames = try framing.append(&incoming)
    } catch {
      throw IMAPTransportError.malformedResponse(String(describing: error))
    }

    var events: [IMAPServerEvent] = []
    for frame in frames {
      switch frame {
      case .complete(var buffer), .literalChunk(var buffer, _):
        try events.append(contentsOf: parse(&buffer))
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

      guard let parsed else { break }
      if let event = map(parsed) {
        events.append(event)
      }
      // Guard against a parser that consumed nothing — without this an
      // unconsumable frame spins this loop forever, on a background sync, with
      // no way for the user to tell.
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
      // `UnknownMessageIdentifier` -> `UID` via the public conversion init;
      // `UID.rawValue` is public. `UIDValidity.rawValue` is NOT (it is
      // `@usableFromInline`), hence the `UInt32(...)` conversion below.
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
      // This is the literal reassembly. The parser hands the body over in as
      // many chunks as the network delivered it in.
      pendingBody.append(contentsOf: buffer.readableBytesView)
      return nil

    case .streamingEnd, .simpleAttribute:
      return nil

    case .finish:
      defer {
        pendingUID = nil
        pendingBody = []
      }
      // No UID means no `SourceRef`, so the message is dropped rather than
      // ingested under a fabricated identity — a wrong externalID would break
      // re-ingest idempotence silently.
      guard let uid = pendingUID, !pendingBody.isEmpty else { return nil }
      return .fetchedMessage(uid: uid, bytes: pendingBody)
    }
  }
}
