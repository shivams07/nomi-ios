import Foundation
import NIOCore
import NIOIMAP

/// Turns raw server bytes into `IMAPServerEvent`s using swift-nio-imap.
///
/// **One stage, not two.** Bytes accumulate in `pending` and are handed straight
/// to `ResponseParser.parseResponseStream`, called in a loop until it returns
/// `nil`. That is the same shape as the library's own client read path —
/// `IMAPClientHandler` -> `NIOSingleStepByteToMessageProcessor<ResponseDecoder>`
/// -> `ResponseParser`, over a raw accumulating buffer with no framing stage
/// anywhere in front of it.
///
/// **Design §2.15 put `FramingParser` in front of the parser. That was wrong,
/// and CI is what proved it: `FramingParser` is the SERVER side.** `FrameDecoder`,
/// which wraps it, is only ever paired with `IMAPServerHandler` — it frames
/// incoming *commands*. Nothing on the client response path uses it, because
/// `ResponseParser` is already literal-aware: it reads the `{115}` itself and
/// streams the body out as `.streamingBytes`.
///
/// The symptom was total and uniform: no `.fetchedMessage` was ever produced for
/// a literal body, at any size, at any chunk boundary, while every non-literal
/// response came through fine. Nine reader tests failed for that one reason.
///
/// The framer cannot be left in "just in case" either — its output is not
/// byte-preserving. `FramingIntegrationTests` asserts `.complete("A1 NOOP\r")`
/// for a CR|LF split and documents the dropped LF as legitimate, so a stage that
/// forwards frames corrupts the stream it forwards.
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
  /// - `bufferLimit` — **assigned at `ResponseParser.swift:189` and read
  ///   nowhere** at 0.4.0, despite a doc comment promising it throws. It
  ///   enforces nothing. Passed anyway so the value is sane if upstream starts
  ///   honouring it — but it is *not* the ceiling, which is why the next one
  ///   exists.
  /// - `accumulationBufferLimit` — **ours, enforced here, and the only ceiling
  ///   the read path has.** Derivation on `Limits.defaultAccumulationBufferLimit`
  ///   (§2.17). It replaces the framer's `bufferSizeLimit`, which went with the
  ///   framer: dropping that stage without reinstating its ceiling would have
  ///   left nothing at all bounding what we buffer from a server.
  public struct Limits: Sendable {
    public var bodySizeLimit: UInt64
    public var literalSizeLimit: Int
    public var bufferLimit: Int
    public var accumulationBufferLimit: Int

    /// The ceiling on bytes held while no complete response can be parsed out of
    /// them. 256 KB, per design §2.17.
    ///
    /// **It does not cap a message body**, and nobody should "fix" it thinking
    /// it does: a literal never sits here, because `ResponseParser` drains it as
    /// `.streamingBytes` as it arrives — a 400 KB body fed in one `consume` is
    /// consumed within that call and leaves nothing behind. The memory that
    /// matters for a backfill is the FETCH batch, and that is bounded in
    /// `MailSyncEngine` (§2.17 axis 1), not here.
    ///
    /// It is sized for one case, and the case is `* SEARCH`: **the whole result
    /// of a UID SEARCH is a single line with no CRLF until the end**, so none of
    /// it is parseable until all of it has arrived.
    ///
    /// The derivation, and why 256 KB rather than something snug:
    ///
    /// - `* SEARCH ` + 3,000 four-digit UIDs measures **15,010 bytes** — already
    ///   past the 8192 the library defaults to elsewhere, on a modest mailbox.
    /// - A long-lived Gmail INBOX hands out **6- and 7-digit UIDs**, and six busy
    ///   months is nearer 10,000–15,000 messages than 3,000. At 8 bytes per UID
    ///   (7 digits + separator) that is **~120 KB on one line**.
    /// - 256 KB is ~32,000 seven-digit UIDs: about twice the realistic worst case.
    ///
    /// So this is a guard against a malformed or hostile server, not a
    /// correctness knob — big enough that tripping it means the response is
    /// wrong, not that the user has a lot of mail. Windowing the SEARCH by month
    /// (§2.17 axis 2) bounds the request as well, but a ceiling on what we will
    /// buffer from a server is not something windowing replaces.
    ///
    /// Covered by `IMAPResponseBufferCeilingTests`.
    public static let defaultAccumulationBufferLimit = 256 * 1024

    public init(
      bodySizeLimit: UInt64 = 25 * 1024 * 1024,
      literalSizeLimit: Int = 1024 * 1024,
      bufferLimit: Int = 1024 * 1024,
      accumulationBufferLimit: Int = Limits.defaultAccumulationBufferLimit
    ) {
      self.bodySizeLimit = bodySizeLimit
      self.literalSizeLimit = literalSizeLimit
      self.bufferLimit = bufferLimit
      self.accumulationBufferLimit = accumulationBufferLimit
    }

    /// The library's own defaults, for the tests that show what changing them
    /// does. Not for shipping.
    public static let libraryDefaults = Limits(
      bodySizeLimit: .max,
      literalSizeLimit: 4_096,
      bufferLimit: 8_192,
      accumulationBufferLimit: 8_192
    )
  }

  private let limits: Limits
  private let lock = NSLock()

  private var parser: ResponseParser

  /// Everything received and not yet parsed off. One buffer for the whole
  /// connection: `parseResponseStream` moves the reader index forward by exactly
  /// what it consumed and leaves the remainder in place, so a response split
  /// across packets simply completes on a later `consume`.
  private var pending = ByteBuffer()

  /// Assembly state for the FETCH currently in flight. A FETCH arrives as
  /// several events — start, attributes, streamed body, finish — and only the
  /// `finish` knows the message is whole.
  private var pendingUID: UInt32?
  private var pendingBody: [UInt8] = []

  public init(limits: Limits = Limits()) {
    self.limits = limits
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
    parser = Self.makeParser(limits)
    pending = ByteBuffer()
    pendingUID = nil
    pendingBody = []
  }

  public func consume(_ bytes: [UInt8]) throws -> [IMAPServerEvent] {
    lock.lock()
    defer { lock.unlock() }

    pending.writeBytes(bytes)

    var events: [IMAPServerEvent] = []
    var stalls = 0

    while pending.readableBytes > 0 {
      let before = pending.readableBytes
      let parsed: ResponseOrContinuationRequest?
      do {
        parsed = try parser.parseResponseStream(buffer: &pending)
      } catch {
        throw IMAPTransportError.malformedResponse(String(describing: error))
      }

      // `nil` means `IncompleteMessage`: the parser rolled its own buffer back,
      // consumed nothing, and wants more bytes. There is nothing further to do
      // with what we have.
      guard let parsed else { break }

      if let event = map(parsed) {
        events.append(event)
      }

      // A parsed response that consumed no bytes is legitimate exactly once in a
      // row: `.streamingEnd` is emitted from a state transition when the
      // literal's byte count reaches zero, before the `)` that follows it is
      // read. Breaking on the first zero-consumption result would stop right
      // there and never reach `.finish` — which is the event that actually
      // yields the message. Repeated stalls are a parser we cannot make progress
      // with, and spinning here would hang a background sync silently.
      if pending.readableBytes == before {
        stalls += 1
        if stalls > 4 { break }
      } else {
        stalls = 0
      }
    }

    pending.discardReadBytes()

    // The ceiling goes here, *after* draining, not on the incoming bytes: a
    // single `consume` carrying a 400 KB body is parsed within this call and
    // leaves nothing behind. What is left is by definition unparseable so far,
    // and that is the thing worth bounding.
    guard pending.readableBytes <= limits.accumulationBufferLimit else {
      throw IMAPTransportError.malformedResponse(
        "\(pending.readableBytes) bytes buffered with no complete response, "
          + "over the \(limits.accumulationBufferLimit)-byte limit")
    }

    return events
  }

  // MARK: -

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
      // many chunks as the network delivered it in, and tracks the literal's
      // remaining byte count itself — there is no second copy of that
      // arithmetic here.
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
