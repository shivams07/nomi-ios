import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// The seam that stops a hangup looking like an empty sync (§2.16).
final class IMAPFetchSequencerTests: XCTestCase {

  private func message(_ uid: UInt32) -> IMAPServerEvent {
    .fetchedMessage(uid: uid, bytes: Array("From: <a@b.com>\r\n\r\nbody\r\n".utf8))
  }

  // MARK: - The happy path

  func testMessagesAreReturnedOnceTheTaggedCompletionArrives() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")

    XCTAssertFalse(try sequencer.apply(message(1)))
    XCTAssertFalse(try sequencer.apply(message(2)))
    XCTAssertTrue(
      try sequencer.apply(.commandCompleted(tag: "a004", status: .ok, text: "Success")))

    XCTAssertEqual(try sequencer.messages().map(\.uid), [1, 2])
  }

  /// Untagged chatter and other commands' completions are not ours.
  func testOtherTagsAndUntaggedEventsAreIgnored() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")

    XCTAssertFalse(try sequencer.apply(.uidValidity(900_100)))
    XCTAssertFalse(try sequencer.apply(.searchResults([1, 2, 3])))
    XCTAssertFalse(try sequencer.apply(.continuationRequest))
    XCTAssertFalse(
      try sequencer.apply(.commandCompleted(tag: "a003", status: .ok, text: "SEARCH completed")))
    XCTAssertFalse(try sequencer.apply(message(7)))
    XCTAssertTrue(try sequencer.apply(.commandCompleted(tag: "a004", status: .ok, text: "ok")))

    XCTAssertEqual(try sequencer.messages().map(\.uid), [7])
  }

  // MARK: - The failure this whole type exists for

  /// A `* BYE` before the tagged completion means the batch is SHORT. Handing
  /// back the messages that happened to arrive would let the engine advance its
  /// cursor past UIDs that were never fetched — data loss that never surfaces.
  func testAServerHangupMidFetchThrowsRatherThanReturningAShortBatch() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")
    XCTAssertFalse(try sequencer.apply(message(1)))

    XCTAssertThrowsError(try sequencer.apply(.connectionClosing(text: "Shutting down"))) {
      guard case IMAPTransportError.serverClosedMidCommand(let tag, _) = $0 else {
        return XCTFail("expected serverClosedMidCommand, got \($0)")
      }
      XCTAssertEqual(tag, "a004")
    }
  }

  /// …and the partial batch stays unreachable afterwards. There is deliberately
  /// no accessor that hands back a half-finished fetch.
  func testAPartialBatchCannotBeReadAfterAHangup() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")
    _ = try sequencer.apply(message(1))
    _ = try? sequencer.apply(.connectionClosing(text: "Shutting down"))

    XCTAssertEqual(sequencer.receivedCount, 1, "the message did arrive…")
    XCTAssertThrowsError(try sequencer.messages(), "…but it must not be readable as a result")
  }

  /// A stream that just stops is the same failure as an explicit BYE.
  func testAStreamThatEndsWithoutCompletionIsAFailureNotAnEmptyResult() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")
    _ = try sequencer.apply(message(1))

    XCTAssertThrowsError(try sequencer.messages()) {
      guard case IMAPTransportError.serverClosedMidCommand = $0 else {
        return XCTFail("expected serverClosedMidCommand, got \($0)")
      }
    }
  }

  func testATaggedFailureThrowsWithItsStatus() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")

    XCTAssertThrowsError(
      try sequencer.apply(.commandCompleted(tag: "a004", status: .no, text: "Invalid messageset"))
    ) {
      guard case IMAPTransportError.commandFailed(_, let status, _) = $0 else {
        return XCTFail("expected commandFailed, got \($0)")
      }
      XCTAssertEqual(status, .no)
    }
  }

  /// An empty fetch that COMPLETED is a legitimate zero — the case the failures
  /// above must stay distinguishable from.
  func testACompletedFetchWithNoMessagesIsAValidEmptyResult() throws {
    var sequencer = IMAPFetchSequencer(tag: "a004")

    XCTAssertTrue(try sequencer.apply(.commandCompleted(tag: "a004", status: .ok, text: "ok")))
    XCTAssertEqual(try sequencer.messages().count, 0)
  }

  // MARK: - Driven by the recorded transcript

  func testTheRecordedSessionsFetchCompletesThroughTheSequencer() throws {
    let transcript = try IMAPTranscript.load("gmail_sync_session.txt")
    let events = try NIOIMAPResponseReader().consume(transcript.serverBytes)

    var sequencer = IMAPFetchSequencer(tag: "a004")
    try sequencer.apply(events)

    let messages = try sequencer.messages()
    XCTAssertEqual(messages.map(\.uid), [4389])

    // `XCTUnwrap`, not `messages[0]`. When this assertion first ran on CI the
    // list came back empty, and the subscript trapped — which kills the test
    // *process*, so every suite after this one was never reached and the log
    // said nothing about why. A test that fails must fail, not crash.
    let first = try XCTUnwrap(messages.first)
    XCTAssertTrue(String(decoding: first.bytes, as: UTF8.self).contains("1,299.50"))
  }
}
