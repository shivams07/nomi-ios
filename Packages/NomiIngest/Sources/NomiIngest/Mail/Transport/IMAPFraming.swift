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

  /// `FramingParser`'s own default is 8192 (`IMAPDefaults.lineLengthLimit`).
  ///
  /// That default does **not** cap a message body: a literal never accumulates
  /// in the framer, because it emits `.insideLiteral` per chunk as it drains.
  /// What the limit actually bounds is a single *unterminated line* — a server
  /// sending megabytes with no CRLF. Raising it is headroom for a long header
  /// line, not a fix for anything.
  public init(bufferSizeLimit: Int = 1024 * 1024) {
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
