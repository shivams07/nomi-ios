import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The fetch path, driven by a recorded server transcript, with no network and
/// no server (U2b's done-when).
///
/// What this proves: the client turns real IMAP server bytes into the events the
/// sync engine needs. What it does NOT prove: that a real server sends these
/// bytes, that TLS negotiates, or that IDLE behaves. Those need a mailbox and
/// nobody on this team has one.
final class NIOIMAPResponseReaderTests: XCTestCase {

  private func reader() -> NIOIMAPResponseReader { NIOIMAPResponseReader() }

  private func events(_ lines: [String]) throws -> [IMAPServerEvent] {
    try reader().consume(Array(lines.map { $0 + "\r\n" }.joined().utf8))
  }

  // MARK: - EXAMINE

  func testUIDValidityAndUIDNextAreReadFromTheExamineResponse() throws {
    let events = try events([
      "* FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)",
      "* 4218 EXISTS",
      "* OK [UIDVALIDITY 900100] UIDs valid",
      "* OK [UIDNEXT 4392] Predicted next UID",
      "a002 OK [READ-ONLY] EXAMINE completed",
    ])

    XCTAssertTrue(events.contains(.uidValidity(900_100)))
    XCTAssertTrue(events.contains(.uidNext(4392)))
    XCTAssertTrue(
      events.contains(.commandCompleted(tag: "a002", status: .ok, text: "EXAMINE completed")))
  }

  // MARK: - UID SEARCH

  func testSearchResultsAreReadAsUIDs() throws {
    let events = try events([
      "* SEARCH 4388 4389 4390 4391",
      "a003 OK SEARCH completed",
    ])

    XCTAssertEqual(events.first, .searchResults([4388, 4389, 4390, 4391]))
  }

  func testAnEmptySearchYieldsAnEmptyListRatherThanNothing() throws {
    let events = try events([
      "* SEARCH",
      "a003 OK SEARCH completed",
    ])

    XCTAssertTrue(events.contains(.searchResults([])))
  }

  // MARK: - UID FETCH: the literal

  /// The reason the raw stream goes to `ResponseParser` rather than through any
  /// line splitter. The literal below contains blank lines and CRLFs of its own
  /// — split it on line boundaries and the message is silently truncated at its
  /// first header break, which is every email. `ResponseParser` reads the
  /// `{size}` itself and streams the body out, so it never sees a line there.
  func testAFetchedMessageIsReassembledFromItsLiteralIncludingBlankLines() throws {
    let message =
      "From: <alerts@hdfcbank.net>\r\n"
      + "Subject: Transaction alert\r\n"
      + "\r\n"
      + "Rs. 1,299.50 has been debited from account no. XX4471.\r\n"

    let wire =
      "* 4211 FETCH (UID 4389 BODY[] {\(message.utf8.count)}\r\n"
      + message
      + ")\r\n"
      + "a004 OK Success\r\n"

    let events = try reader().consume(Array(wire.utf8))

    guard case .fetchedMessage(let uid, let bytes)? = events.first(where: {
      if case .fetchedMessage = $0 { return true }
      return false
    }) else {
      return XCTFail("no message was reassembled from \(events)")
    }

    XCTAssertEqual(uid, 4389)
    XCTAssertEqual(String(decoding: bytes, as: UTF8.self), message)
  }

  /// The parsed bytes go to `RFC822Message` and nothing else, so the whole
  /// transport-to-transaction path is exercised here without a server.
  func testAFetchedMessageParsesStraightThroughToATransactionDraft() throws {
    let message =
      "From: HDFC Bank InstaAlerts <alerts@hdfcbank.net>\r\n"
      + "Subject: Debit transaction alert\r\n"
      + "Date: Sat, 15 Aug 2026 08:30:45 +0530\r\n"
      + "Content-Type: text/plain; charset=UTF-8\r\n"
      + "\r\n"
      + "Rs. 1,299.50 has been debited from account no. XX4471 "
      + "to VPA bigbasket@okhdfcbank on 15-08-2026.\r\n"

    let wire =
      "* 4211 FETCH (UID 4389 BODY[] {\(message.utf8.count)}\r\n" + message + ")\r\n"

    let events = try reader().consume(Array(wire.utf8))
    guard case .fetchedMessage(let uid, let bytes)? = events.first else {
      return XCTFail("no message in \(events)")
    }

    let parsed = try RFC822Message.parse(Data(bytes), uid: uid, uidValidity: 900_100)
    let draft = try XCTUnwrap(MailTransactionExtractor().outcome(for: parsed).draft)

    XCTAssertEqual(draft.amountMinor, 129_950)
    XCTAssertEqual(draft.direction, .debit)
    XCTAssertEqual(draft.externalID, "INBOX/900100/4389")
  }

  /// Real sockets deliver arbitrary slices. The reader has to buffer across
  /// them, so the same bytes split every possible way must give the same result.
  func testAMessageSplitAcrossArbitraryPacketBoundariesIsStillReassembled() throws {
    let message = "From: <a@b.com>\r\n\r\nbody line one\r\n\r\nbody line two\r\n"
    let wire = "* 1 FETCH (UID 77 BODY[] {\(message.utf8.count)}\r\n" + message + ")\r\n"
    let bytes = Array(wire.utf8)

    for chunkSize in [1, 3, 7, 16, 64, bytes.count] {
      let reader = self.reader()
      var collected: [IMAPServerEvent] = []
      var index = 0
      while index < bytes.count {
        let end = min(index + chunkSize, bytes.count)
        collected += try reader.consume(Array(bytes[index..<end]))
        index = end
      }

      guard case .fetchedMessage(let uid, let body)? = collected.first(where: {
        if case .fetchedMessage = $0 { return true }
        return false
      }) else {
        return XCTFail("chunk size \(chunkSize) lost the message: \(collected)")
      }
      XCTAssertEqual(uid, 77, "chunk size \(chunkSize)")
      XCTAssertEqual(String(decoding: body, as: UTF8.self), message, "chunk size \(chunkSize)")
    }
  }

  // MARK: - The limits, and what they actually gate

  /// **A correction to my own earlier finding, kept as a test so it cannot
  /// quietly revert.**
  ///
  /// I reported that `ResponseParser`'s 4096-byte `literalSizeLimit` default
  /// would reject ordinary bank mail. It does not. At 0.4.0 the FETCH body is
  /// sized against `GrammarParser.messageBodySizeLimit` (default `.max`), which
  /// `ResponseParser.Options` cannot even set; `literalSizeLimit` gates other
  /// literals. A 40 KB body is accepted with the parser knobs at their library
  /// defaults, and this test says so out loud.
  func testTheLibraryDefaultLiteralLimitDoesNotRejectALargeMessageBody() throws {
    let atLibraryDefaults = NIOIMAPResponseReader(
      limits: .init(
        bodySizeLimit: .max,
        literalSizeLimit: 4_096,
        bufferLimit: 8_192,
        accumulationBufferLimit: 1024 * 1024
      )
    )

    let events = try atLibraryDefaults.consume(Array(Self.wire(bodyBytes: 40_000).utf8))

    XCTAssertTrue(
      events.contains { if case .fetchedMessage = $0 { return true } else { return false } },
      "40 KB was rejected at the library literal limit — the original finding would be right")
  }

  /// `bodySizeLimit` is the one knob here that is genuinely enforced
  /// (`guardStreamingSizeLimit`, strict `<`). Its library default is
  /// `UInt64.max`, so shipping 25 MB is a deliberate TIGHTENING, not a fix.
  ///
  /// Discriminating both ways: below the limit the message arrives, at or above
  /// it the read fails loudly rather than returning an empty result.
  func testBodySizeLimitIsEnforcedAndIsATighteningNotAFix() throws {
    let capped = NIOIMAPResponseReader(limits: .init(bodySizeLimit: 10_000))

    XCTAssertThrowsError(try capped.consume(Array(Self.wire(bodyBytes: 40_000).utf8))) { error in
      guard case IMAPTransportError.malformedResponse = error else {
        return XCTFail("expected a surfaced parse failure, got \(error)")
      }
    }

    let under = try NIOIMAPResponseReader(limits: .init(bodySizeLimit: 10_000))
      .consume(Array(Self.wire(bodyBytes: 500).utf8))
    XCTAssertTrue(
      under.contains { if case .fetchedMessage = $0 { return true } else { return false } })
  }

  /// The shipping limits accept a message far larger than any bank alert.
  func testTheShippingLimitsAcceptAnOrdinaryAndAVeryLargeMessage() throws {
    for size in [4_000, 40_000, 400_000] {
      let events = try reader().consume(Array(Self.wire(bodyBytes: size).utf8))
      XCTAssertTrue(
        events.contains { if case .fetchedMessage = $0 { return true } else { return false } },
        "a \(size)-byte body was rejected")
    }
  }

  /// One FETCH, fed **one byte at a time**, so the body can only arrive as a
  /// long run of `.streamingBytes` events (§2.16(c)).
  ///
  /// This is the test that catches a reader that reassembles a literal only when
  /// it arrives whole: replayed as a single buffer, such a reader still looks
  /// fine. It is also the shape that proved the framing stage was wrong — with
  /// `FramingParser` in front, *no* chunking produced a message at all.
  func testALargeBodyFedOneByteAtATimeIsReassembledFromItsLiteralChunks() throws {
    let wire = Self.wire(bodyBytes: 20_000)
    let bytes = Array(wire.utf8)
    let reader = self.reader()

    var collected: [IMAPServerEvent] = []
    for byte in bytes {
      collected += try reader.consume([byte])
    }

    guard case .fetchedMessage(let uid, let body)? = collected.first(where: {
      if case .fetchedMessage = $0 { return true }
      return false
    }) else {
      return XCTFail("byte-at-a-time lost the message: \(collected)")
    }
    XCTAssertEqual(uid, 5)
    XCTAssertEqual(body.count, Self.message(bodyBytes: 20_000).utf8.count)
    XCTAssertEqual(String(decoding: body, as: UTF8.self), Self.message(bodyBytes: 20_000))
  }

  // MARK: -

  private static func message(bodyBytes: Int) -> String {
    "From: <alerts@hdfcbank.net>\r\n\r\n" + String(repeating: "x", count: bodyBytes) + "\r\n"
  }

  private static func wire(bodyBytes: Int) -> String {
    let message = self.message(bodyBytes: bodyBytes)
    return "* 1 FETCH (UID 5 BODY[] {\(message.utf8.count)}\r\n" + message + ")\r\n"
  }

  // MARK: - Completion and failure

  func testTaggedFailuresAreReportedWithTheirStatusAndText() throws {
    let events = try events(["a001 NO [AUTHENTICATIONFAILED] Invalid credentials"])

    guard case .commandCompleted(let tag, let status, _)? = events.first else {
      return XCTFail("no completion in \(events)")
    }
    XCTAssertEqual(tag, "a001")
    XCTAssertEqual(status, .no)
  }

  func testBadIsDistinguishedFromNo() throws {
    let events = try events(["a009 BAD Invalid command syntax"])

    guard case .commandCompleted(_, let status, _)? = events.first else {
      return XCTFail("no completion in \(events)")
    }
    XCTAssertEqual(status, .bad)
  }

  /// `* BYE` must be reported, not thrown and not swallowed — the library can
  /// deliver it as either `Response.fatal` or an untagged `.bye` depending on
  /// where in the session it lands, and both have to behave the same.
  func testAServerGoodbyeIsReportedRatherThanThrown() throws {
    let events = try events([
      "* BYE LOGOUT Requested",
      "a005 OK 73 good day (Success)",
    ])

    XCTAssertTrue(
      events.contains { if case .connectionClosing = $0 { return true } else { return false } },
      "\(events)")
    XCTAssertTrue(
      events.contains { if case .commandCompleted = $0 { return true } else { return false } },
      "\(events)")
  }

  func testAContinuationRequestIsSurfacedSoIdleCanProceed() throws {
    let events = try events(["+ idling"])
    XCTAssertEqual(events.first, .continuationRequest)
  }

  // MARK: - The recorded session, end to end

  /// Every server line of the recorded dialogue, fed through in order.
  func testTheRecordedSessionYieldsTheEventsTheSyncEngineNeeds() throws {
    let transcript = try IMAPTranscript.load("gmail_sync_session.txt")
    let events = try reader().consume(transcript.serverBytes)

    XCTAssertTrue(events.contains(.uidValidity(900_100)), "\(events)")
    XCTAssertTrue(events.contains(.searchResults([4388, 4389, 4390, 4391])), "\(events)")
    XCTAssertTrue(
      events.contains {
        if case .fetchedMessage(let uid, _) = $0 { return uid == 4389 }
        return false
      }, "\(events)")
  }

  func testResetDiscardsHalfReceivedState() throws {
    let reader = self.reader()
    // A literal header with none of its bytes: the parser is now mid-message.
    _ = try? reader.consume(Array("* 1 FETCH (UID 9 BODY[] {200}\r\n".utf8))
    reader.reset()

    let events = try reader.consume(Array("* SEARCH 1 2 3\r\na001 OK done\r\n".utf8))
    XCTAssertTrue(events.contains(.searchResults([1, 2, 3])), "\(events)")
  }
}
