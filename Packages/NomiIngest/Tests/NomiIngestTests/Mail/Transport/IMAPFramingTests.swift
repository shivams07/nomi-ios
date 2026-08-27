import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The framing buffer limit, and the one case that actually reaches it.
final class IMAPFramingTests: XCTestCase {

  /// `* SEARCH` with several thousand UIDs, as a six-month backfill returns.
  ///
  /// `base` matters: 4,000 gives the 4-digit UIDs of a young mailbox, 4,000,000
  /// the 7-digit UIDs a long-lived Gmail INBOX actually hands out. The
  /// difference is the whole reason 8192 was never enough (§2.17).
  private static func longSearchLine(uidCount: Int, base: Int = 4_000) -> String {
    "* SEARCH " + (1...uidCount).map { String(base + $0) }.joined(separator: " ") + "\r\n"
  }

  /// **The reason `IMAPFraming` raises `FramingParser`'s 8192 default**, and it
  /// is not the message body.
  ///
  /// A literal never accumulates in the framer, so 8192 does not cap a body. But
  /// `* SEARCH` is a single line, and the first six-month backfill on a real
  /// mailbox returns thousands of UIDs on it. At the library default that line
  /// blows the buffer and the *first run against Shivam's mailbox* fails — the
  /// one run nobody on this team can rehearse.
  func testALongSearchResponseFailsAtTheLibraryDefaultAndParsesAtOurs() throws {
    let line = Self.longSearchLine(uidCount: 3_000)
    XCTAssertGreaterThan(line.utf8.count, 8_192, "the fixture must actually exceed the default")

    // At the library default: the line is still unterminated when the buffer
    // passes 8192, so the framer gives up on it.
    let atDefault = NIOIMAPResponseReader(limits: .init(framingBufferLimit: 8_192))
    XCTAssertThrowsError(try Self.feedInChunks(line, to: atDefault)) { error in
      guard case IMAPTransportError.malformedResponse = error else {
        return XCTFail("expected a surfaced framing failure, got \(error)")
      }
    }

    // At ours: parsed, all 3000 UIDs.
    let events = try Self.feedInChunks(line, to: NIOIMAPResponseReader())
    guard case .searchResults(let uids)? = events.first(where: {
      if case .searchResults = $0 { return true }
      return false
    }) else {
      return XCTFail("no search results in \(events.count) events")
    }
    XCTAssertEqual(uids.count, 3_000)
    XCTAssertEqual(uids.first, 4_001)
    XCTAssertEqual(uids.last, 7_000)
  }

  /// A short SEARCH is fine either way — the limit only bites on the long one.
  func testAShortSearchResponseParsesAtTheLibraryDefaultToo() throws {
    let events = try Self.feedInChunks(
      Self.longSearchLine(uidCount: 20),
      to: NIOIMAPResponseReader(limits: .init(framingBufferLimit: 8_192)))

    XCTAssertTrue(
      events.contains { if case .searchResults = $0 { return true } else { return false } })
  }

  /// The ceiling is a derivation, not a taste — 256 KB is ~32,000 seven-digit
  /// UIDs, about twice the realistic worst case (§2.17). Pinned so that moving
  /// it is a deliberate act with a test to update, in either direction: down to
  /// something snug enough to fail on a big mailbox, or up to a number that
  /// stops being a guard at all.
  func testTheCeilingIsTheDerivedValueAndTheReaderUsesIt() {
    XCTAssertEqual(IMAPFraming.defaultBufferSizeLimit, 256 * 1024)
    XCTAssertEqual(
      NIOIMAPResponseReader.Limits().framingBufferLimit, IMAPFraming.defaultBufferSizeLimit,
      "the shipping reader must use the derived ceiling, not its own number")
  }

  /// The case the ceiling was sized for: six busy months of a long-lived Gmail
  /// INBOX — 15,000 messages, 7-digit UIDs, one line, ~120 KB.
  ///
  /// This is the assertion that matters after lowering the ceiling from 1 MiB to
  /// 256 KB. The old value could not plausibly be reached; the new one is within
  /// an order of magnitude of real traffic, so the realistic worst case has to be
  /// shown fitting under it rather than assumed to.
  func testTheRealisticWorstCaseSearchLineFitsUnderTheCeiling() throws {
    let line = Self.longSearchLine(uidCount: 15_000, base: 4_000_000)
    XCTAssertGreaterThan(line.utf8.count, 120_000, "the fixture must be the ~120 KB case")
    XCTAssertLessThan(line.utf8.count, IMAPFraming.defaultBufferSizeLimit)

    let events = try Self.feedInChunks(line, to: NIOIMAPResponseReader())
    guard case .searchResults(let uids)? = events.first(where: {
      if case .searchResults = $0 { return true }
      return false
    }) else {
      return XCTFail("no search results in \(events.count) events")
    }
    XCTAssertEqual(uids.count, 15_000)
    XCTAssertEqual(uids.last, 4_015_000)
  }

  /// And the ceiling is still a ceiling. A server that never terminates the line
  /// must be cut off rather than buffered until the app is killed — which is the
  /// only thing this limit is for now that windowing bounds the request (§2.17).
  func testALineBeyondTheCeilingIsRejected() {
    let line = Self.longSearchLine(uidCount: 40_000, base: 4_000_000)
    XCTAssertGreaterThan(line.utf8.count, IMAPFraming.defaultBufferSizeLimit)

    XCTAssertThrowsError(try Self.feedInChunks(line, to: NIOIMAPResponseReader())) { error in
      guard case IMAPTransportError.malformedResponse = error else {
        return XCTFail("expected a surfaced framing failure, got \(error)")
      }
    }
  }

  /// Fed in pieces, because that is how a socket delivers it and it is the only
  /// way the buffer accumulates rather than framing in one go.
  private static func feedInChunks(
    _ text: String, to reader: NIOIMAPResponseReader, chunk: Int = 512
  ) throws -> [IMAPServerEvent] {
    let bytes = Array(text.utf8)
    var events: [IMAPServerEvent] = []
    var index = 0
    while index < bytes.count {
      let end = min(index + chunk, bytes.count)
      events += try reader.consume(Array(bytes[index..<end]))
      index = end
    }
    return events
  }
}
