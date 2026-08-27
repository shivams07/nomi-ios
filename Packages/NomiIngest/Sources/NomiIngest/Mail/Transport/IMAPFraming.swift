import Foundation
import NIOCore

// ============================================================================
// THE ONLY @_spi IMPORT IN THIS PROJECT. Keep it that way (design §2.16).
//
// `FramingParser`'s *type* is public and Sendable, but its `init` and its
// `appendAndFrameBuffer` are both `@_spi(NIOIMAPInternal)`, so reaching them
// needs this import rather than a plain one. SPI carries no semver promise —
// upstream can drop it in a patch release — so it is confined to this file and
// wrapped behind `IMAPFraming`, which is ordinary Swift. If the SPI disappears,
// this one file is the blast radius and everything above it is unaffected.
//
// `Package.swift` pins swift-nio-imap with `.upToNextMinor(from: "0.4.0")` for
// the same reason (§2.16).
// ============================================================================
@_spi(NIOIMAPInternal) import NIOIMAP

/// One frame of IMAP wire data, with the SPI type mapped to something plain.
public enum IMAPFrame: Sendable {
  /// A complete line or response.
  case complete(ByteBuffer)
  /// A chunk of a literal's payload, and how many of its bytes are still to
  /// come. A `FETCH BODY.PEEK[]` body arrives as a run of these.
  case literalChunk(ByteBuffer, remainingBytes: UInt64)
  /// Bytes that can never form a valid response.
  case invalid(ByteBuffer)
}

/// Splits an IMAP byte stream into frames.
///
/// This is the piece worth borrowing rather than writing. IMAP literals are
/// `{123}` followed by exactly 123 octets which may themselves contain CRLF and
/// must not be line-split — and a `FETCH BODY.PEEK[]` response is made of
/// precisely that. A hand-rolled line splitter truncates every email at its
/// first blank line.
public struct IMAPFraming {
  private var parser: FramingParser

  /// The ceiling on one unterminated line, replacing `FramingParser`'s own
  /// default of 8192 (`IMAPDefaults.lineLengthLimit`). 256 KB, per design §2.17.
  ///
  /// **It does not cap a message body**, and nobody should "fix" it thinking it
  /// does: a literal never accumulates in the framer, which emits
  /// `.insideLiteral` per chunk as it drains. The memory that matters for a
  /// backfill is the FETCH batch, and that is bounded in `MailSyncEngine`
  /// (§2.17 axis 1), not here.
  ///
  /// It is raised for one case, and the case is `* SEARCH`: **the whole result
  /// of a UID SEARCH is a single line with no CRLF until the end.**
  ///
  /// The derivation, and why 256 KB rather than something snug:
  ///
  /// - `* SEARCH ` + 3,000 four-digit UIDs measures **15,010 bytes** — already
  ///   past 8192, on a modest mailbox.
  /// - A long-lived Gmail INBOX hands out **6- and 7-digit UIDs**, and six busy
  ///   months is nearer 10,000–15,000 messages than 3,000. At 8 bytes per UID
  ///   (7 digits + separator) that is **~120 KB on one line**.
  /// - 256 KB is ~32,000 seven-digit UIDs: about twice the realistic worst case.
  ///
  /// So this is a guard against a malformed or hostile server, not a correctness
  /// knob — big enough that tripping it means the response is wrong, not that
  /// the user has a lot of mail. Windowing the SEARCH by month (§2.17 axis 2)
  /// bounds the request as well, but a ceiling on what we will buffer from a
  /// server is not something windowing replaces.
  ///
  /// At the library's 8192 the framer throws `PayloadTooLargeError` and the
  /// *first run on a real mailbox* fails — the one run nobody here can rehearse.
  /// Covered by `IMAPFramingTests`.
  public static let defaultBufferSizeLimit = 256 * 1024

  public init(bufferSizeLimit: Int = IMAPFraming.defaultBufferSizeLimit) {
    parser = FramingParser(bufferSizeLimit: bufferSizeLimit)
  }

  /// Appends bytes and returns every frame they completed.
  ///
  /// `.incomplete` is deliberately not surfaced: it means "need more bytes",
  /// the framer has kept the partial frame, and there is nothing for a caller
  /// to do about it.
  public mutating func append(_ buffer: inout ByteBuffer) throws -> [IMAPFrame] {
    try parser.appendAndFrameBuffer(&buffer).compactMap { result in
      switch result {
      case .complete(let buffer):
        return .complete(buffer)
      case .insideLiteral(let buffer, let remaining):
        return .literalChunk(buffer, remainingBytes: remaining)
      case .invalid(let buffer):
        return .invalid(buffer)
      case .incomplete:
        return nil
      }
    }
  }
}
