import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The framing buffer limit, and the one case that actually reaches it.
final class IMAPFramingTests: XCTestCase {

  /// `* SEARCH` with several thousand UIDs, as a six-month backfill returns.
  private static func longSearchLine(uidCount: Int) -> String {
    "* SEARCH " + (1...uidCount).map { String(4000 + $0) }.joined(separator: " ") + "\r\n"
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
