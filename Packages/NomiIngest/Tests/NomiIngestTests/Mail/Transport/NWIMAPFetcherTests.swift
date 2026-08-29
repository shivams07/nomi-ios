import Foundation
import Network
import NomiCore
import XCTest

@testable import NomiIngest

/// A scripted `IMAPByteChannel`: replies come from a queue, and every operation
/// is recorded.
///
/// This is the whole reason `IMAPByteChannel` exists. Everything `NWIMAPFetcher`
/// decides — which command it writes, how it matches a tagged completion, what
/// it does when the server hangs up mid-fetch, whether it reassembles a literal
/// split across packets — is exercised here. What is *not* exercised is
/// `NWConnectionChannel` itself, and this unit's PR says so in those words.
///
/// Replies are queued in order and handed out a chunk at a time. That models the
/// real thing accurately for a request/response protocol with no pipelining:
/// the fetcher reads only as far as its own tagged completion, so the next
/// command's reply simply waits in the queue.
private final class ScriptedChannel: IMAPByteChannel, @unchecked Sendable {
  enum Operation: Equatable {
    case open(host: String, port: Int)
    case send([UInt8])
    case receive
    case close
  }

  private let lock = NSLock()
  private var replies: [[UInt8]] = []
  private var log: [Operation] = []

  init(replies: [String] = [], chunkSize: Int? = nil) {
    self.replies = replies.flatMap { Self.chunked(Array($0.utf8), size: chunkSize) }
  }

  init(rawReplies: [[UInt8]], chunkSize: Int? = nil) {
    self.replies = rawReplies.flatMap { Self.chunked($0, size: chunkSize) }
  }

  private static func chunked(_ bytes: [UInt8], size: Int?) -> [[UInt8]] {
    guard let size, size > 0, bytes.count > size else { return [bytes] }
    return stride(from: 0, to: bytes.count, by: size).map {
      Array(bytes[$0..<min($0 + size, bytes.count)])
    }
  }

  var operations: [Operation] {
    lock.lock()
    defer { lock.unlock() }
    return log
  }

  /// Everything written to the socket, concatenated — the exact wire bytes.
  var sentText: String {
    lock.lock()
    defer { lock.unlock() }
    let bytes = log.compactMap { operation -> [UInt8]? in
      if case .send(let payload) = operation { return payload }
      return nil
    }.flatMap { $0 }
    return String(decoding: bytes, as: UTF8.self)
  }

  func open(host: String, port: Int) async throws {
    lock.lock()
    log.append(.open(host: host, port: port))
    lock.unlock()
  }

  func send(_ bytes: [UInt8]) async throws {
    lock.lock()
    log.append(.send(bytes))
    lock.unlock()
  }

  func receive() async throws -> [UInt8] {
    lock.lock()
    log.append(.receive)
    guard !replies.isEmpty else {
      lock.unlock()
      throw IMAPTransportError.connectionClosed
    }
    let next = replies.removeFirst()
    lock.unlock()
    return next
  }

  func close() async {
    lock.lock()
    log.append(.close)
    lock.unlock()
  }
}

private let credentials = IMAPCredentials(
  host: "imap.gmail.com", port: 993, address: "someone@gmail.com", password: "abcd efgh ijkl mnop")

private let loginOK = "* OK Gimap ready for requests\r\na001 OK someone@gmail.com authenticated\r\n"
private let examineOK = """
  * FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)\r
  * 4218 EXISTS\r
  * OK [UIDVALIDITY 900100] UIDs valid\r
  * OK [UIDNEXT 4392] Predicted next UID\r
  a002 OK [READ-ONLY] EXAMINE completed\r\n
  """

final class NWIMAPFetcherTests: XCTestCase {

  private func connected(
    replies: [String], chunkSize: Int? = nil
  ) async throws -> (NWIMAPFetcher, ScriptedChannel) {
    let channel = ScriptedChannel(replies: [loginOK] + replies, chunkSize: chunkSize)
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())
    try await fetcher.connect(credentials)
    return (fetcher, channel)
  }

  // MARK: - Connect

  /// The wire form, byte for byte. A password containing a quote or a backslash
  /// must be escaped or the rest of it becomes command syntax.
  func testLoginIsWrittenAsQuotedStringsWithCRLF() async throws {
    let (_, channel) = try await connected(replies: [])
    XCTAssertEqual(
      channel.sentText,
      "a001 LOGIN \"someone@gmail.com\" \"abcd efgh ijkl mnop\"\r\n")
  }

  func testTheSocketIsOpenedOnTheCredentialsHostAndPort() async throws {
    let (_, channel) = try await connected(replies: [])
    XCTAssertEqual(channel.operations.first, .open(host: "imap.gmail.com", port: 993))
  }

  /// A rejected app password is the one failure here with a user action
  /// attached, so it gets its own error rather than the generic `commandFailed`
  /// — `IMAPMailConnectionService` maps it to `MailError.authenticationFailed`.
  func testARejectedLoginBecomesAuthenticationFailed() async {
    let channel = ScriptedChannel(replies: [
      "* OK Gimap ready\r\na001 NO [AUTHENTICATIONFAILED] Invalid credentials\r\n"
    ])
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())

    do {
      try await fetcher.connect(credentials)
      XCTFail("expected authenticationFailed")
    } catch let error as IMAPTransportError {
      guard case .authenticationFailed = error else {
        return XCTFail("expected authenticationFailed, got \(error)")
      }
    } catch {
      XCTFail("expected IMAPTransportError, got \(error)")
    }
  }

  /// A failed connect must not leave a socket open — the next attempt opens a
  /// fresh one, and a leaked connection holds a TLS session for a mailbox the
  /// user was just told they are not connected to.
  func testAFailedLoginClosesTheSocket() async {
    let channel = ScriptedChannel(replies: ["* OK ready\r\na001 NO nope\r\n"])
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())
    try? await fetcher.connect(credentials)

    XCTAssertTrue(channel.operations.contains(.close))
  }

  /// A server that greets with `* BYE` is refusing the connection. It must not
  /// look like a successful connect with nothing in the mailbox.
  func testAByeGreetingFailsTheConnect() async {
    let channel = ScriptedChannel(replies: ["* BYE Too many simultaneous connections\r\n"])
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())

    do {
      try await fetcher.connect(credentials)
      XCTFail("expected a failure")
    } catch let error as IMAPTransportError {
      guard case .serverClosedMidCommand = error else {
        return XCTFail("expected serverClosedMidCommand, got \(error)")
      }
    } catch {
      XCTFail("unexpected \(error)")
    }
  }

  // MARK: - EXAMINE

  func testExamineIsWrittenAsQuotedMailboxAndReadsUIDValidity() async throws {
    let (fetcher, channel) = try await connected(replies: [examineOK])

    let state = try await fetcher.selectMailbox("INBOX")

    XCTAssertTrue(channel.sentText.hasSuffix("a002 EXAMINE \"INBOX\"\r\n"), channel.sentText)
    XCTAssertEqual(state.uidValidity, 900_100)
    XCTAssertEqual(state.uidNext, 4392)
    XCTAssertEqual(state.name, "INBOX")
  }

  /// `EXAMINE`, never `SELECT` (R4) — the app has no business marking mail read
  /// in a mailbox it does not own, and read-only-by-construction beats
  /// remembering not to write.
  func testTheMailboxIsOpenedReadOnly() async throws {
    let (fetcher, channel) = try await connected(replies: [examineOK])
    _ = try await fetcher.selectMailbox("INBOX")

    XCTAssertFalse(channel.sentText.contains("SELECT"), channel.sentText)
    XCTAssertTrue(channel.sentText.contains("EXAMINE"))
  }

  /// The whole UID cursor is meaningless without UIDVALIDITY, so a server that
  /// omits it is malformed rather than a mailbox with a default of zero.
  func testExamineWithoutUIDValidityIsMalformedRatherThanDefaulted() async throws {
    let (fetcher, _) = try await connected(replies: ["a002 OK [READ-ONLY] EXAMINE completed\r\n"])

    do {
      _ = try await fetcher.selectMailbox("INBOX")
      XCTFail("expected malformedResponse")
    } catch let error as IMAPTransportError {
      guard case .malformedResponse = error else {
        return XCTFail("expected malformedResponse, got \(error)")
      }
    }
  }

  /// Re-EXAMINE per batch would be a wasted round trip on every fetch of a
  /// backfill; re-EXAMINE on a mailbox change is mandatory, because UID FETCH
  /// applies to whatever is currently selected.
  func testTheMailboxIsReExaminedOnlyWhenItChanges() async throws {
    let archive = examineOK
      .replacingOccurrences(of: "a002", with: "a004")
      .replacingOccurrences(of: "900100", with: "900200")
    let (fetcher, channel) = try await connected(replies: [
      examineOK,
      "* SEARCH 1\r\na003 OK SEARCH completed\r\n",
      archive,
      "* SEARCH 2\r\na005 OK SEARCH completed\r\n",
    ])

    _ = try await fetcher.selectMailbox("INBOX")
    _ = try await fetcher.uids(after: 0, in: "INBOX")
    _ = try await fetcher.uids(after: 0, in: "[Gmail]/All Mail")

    XCTAssertEqual(channel.sentText.components(separatedBy: "EXAMINE").count - 1, 2, channel.sentText)
  }

  // MARK: - UID SEARCH

  func testUidSearchSinceUsesTheIMAPDateForm() async throws {
    let (fetcher, channel) = try await connected(replies: [
      examineOK,
      "* SEARCH 4388 4389 4390\r\na003 OK SEARCH completed\r\n",
    ])

    let uids = try await fetcher.uids(
      since: Date(timeIntervalSince1970: 1_754_000_000), in: "INBOX")

    XCTAssertEqual(uids, [4388, 4389, 4390])
    XCTAssertTrue(channel.sentText.contains("a003 UID SEARCH SINCE 01-Aug-2025\r\n"), channel.sentText)
  }

  func testWindowedSearchSendsBothBounds() async throws {
    let (fetcher, channel) = try await connected(replies: [
      examineOK,
      "* SEARCH\r\na003 OK SEARCH completed\r\n",
    ])

    _ = try await fetcher.uids(
      since: Date(timeIntervalSince1970: 1_754_000_000),
      before: Date(timeIntervalSince1970: 1_756_600_000),
      in: "INBOX")

    XCTAssertTrue(
      channel.sentText.contains("a003 UID SEARCH SINCE 01-Aug-2025 BEFORE 31-Aug-2025\r\n"),
      channel.sentText)
  }

  /// `UID SEARCH UID n+1:*` always matches at least the highest existing UID
  /// even when nothing is new — `*` means "the last message", not "nothing".
  /// Without the filter the engine re-ingests one message on every idle sync.
  func testUidSearchAfterExcludesTheCursorItself() async throws {
    let (fetcher, _) = try await connected(replies: [
      examineOK,
      "* SEARCH 4391 4392 4393\r\na003 OK SEARCH completed\r\n",
    ])

    let uids = try await fetcher.uids(after: 4391, in: "INBOX")

    XCTAssertEqual(uids, [4392, 4393])
  }

  /// A server may split results over more than one untagged line. Taking the
  /// last would drop most of a backfill.
  func testSearchResultsAccumulateAcrossMultipleUntaggedLines() async throws {
    let (fetcher, _) = try await connected(replies: [
      examineOK,
      "* SEARCH 1 2\r\n* SEARCH 3 4\r\na003 OK SEARCH completed\r\n",
    ])

    let uids = try await fetcher.uids(after: 0, in: "INBOX")

    XCTAssertEqual(uids, [1, 2, 3, 4])
  }

  // MARK: - UID FETCH

  /// **`BODY.PEEK[]`, never `BODY[]`** (R4). `BODY[]` sets `\Seen` on the
  /// user's real mail as a side effect of scanning it — visible, annoying and
  /// not undoable. Asserted on the bytes actually written, not on the builder.
  func testFetchWritesBodyPeekAndACollapsedUIDSet() async throws {
    let (fetcher, channel) = try await connected(replies: [
      examineOK,
      "a003 OK FETCH completed\r\n",
    ])

    _ = try await fetcher.fetch(uids: [4, 5, 6, 9], in: "INBOX")

    XCTAssertTrue(
      channel.sentText.contains("a003 UID FETCH 4:6,9 (UID BODY.PEEK[])\r\n"), channel.sentText)
    XCTAssertFalse(channel.sentText.contains("BODY[]"), "a bare BODY[] would set \\Seen")
  }

  /// The engine bounds a batch so only one batch of bodies is resident (§2.17).
  /// A transport that re-chunked or read ahead would put that ceiling back.
  func testAnEmptyBatchIssuesNoCommandAtAll() async throws {
    let (fetcher, channel) = try await connected(replies: [])

    let messages = try await fetcher.fetch(uids: [], in: "INBOX")

    XCTAssertTrue(messages.isEmpty)
    XCTAssertFalse(channel.sentText.contains("FETCH"))
  }

  /// The acceptance criterion: a message delivered as a literal in small chunks
  /// reassembles whole. One byte at a time is the harshest split there is, and
  /// it lands mid-literal-header, mid-body and mid-CRLF.
  func testALiteralDeliveredOneByteAtATimeReassemblesWhole() async throws {
    let body = "From: alerts@hdfcbank.net\r\nSubject: Txn alert\r\n\r\nRs 450.00 debited\r\n\r\nthanks\r\n"
    let fetchReply = "* 1 FETCH (UID 4389 BODY[] {\(body.utf8.count)}\r\n" + body + ")\r\na003 OK FETCH completed\r\n"

    let channel = ScriptedChannel(replies: [loginOK, examineOK, fetchReply], chunkSize: 1)
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())
    try await fetcher.connect(credentials)

    let messages = try await fetcher.fetch(uids: [4389], in: "INBOX")

    XCTAssertEqual(messages.count, 1)
    let message = try XCTUnwrap(messages.first)
    XCTAssertEqual(message.uid, 4389)
    XCTAssertEqual(message.uidValidity, 900_100)
    XCTAssertEqual(message.fromRaw, "alerts@hdfcbank.net")
    XCTAssertEqual(message.subject, "Txn alert")
    XCTAssertTrue(message.textBody?.contains("Rs 450.00 debited") == true, "\(message)")
    // The blank line and the second paragraph survive — a line-splitting reader
    // truncates here, at the first header break, which is every email.
    XCTAssertTrue(message.textBody?.contains("thanks") == true, "\(message)")
  }

  /// Same message, several chunk sizes. The sizes that break a naive reader are
  /// the ones that land between the CR and the LF of the literal header, so a
  /// single chunk size proves very little.
  func testTheSameMessageSurvivesEveryChunkSize() async throws {
    let body = "From: <a@b.com>\r\nSubject: s\r\n\r\nbody line one\r\n\r\nbody line two\r\n"
    let fetchReply = "* 1 FETCH (UID 77 BODY[] {\(body.utf8.count)}\r\n" + body + ")\r\na003 OK FETCH completed\r\n"

    for chunkSize in [1, 2, 3, 7, 16, 64, 4096] {
      let channel = ScriptedChannel(replies: [loginOK, examineOK, fetchReply], chunkSize: chunkSize)
      let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())
      try await fetcher.connect(credentials)

      let messages = try await fetcher.fetch(uids: [77], in: "INBOX")
      XCTAssertEqual(messages.count, 1, "chunk size \(chunkSize) lost the message")
      XCTAssertTrue(
        messages.first?.textBody?.contains("body line two") == true,
        "chunk size \(chunkSize) truncated the body")
    }
  }

  /// A body that is valid ISO-8859-1 and invalid UTF-8. Decoding it with
  /// `String(decoding:as: UTF8.self)` would substitute U+FFFD and silently
  /// corrupt exactly the bank mail this app exists to read.
  func testALatin1BodyIsDecodedRatherThanReplacedWithU_FFFD() async throws {
    var bodyBytes = Array("From: <a@b.com>\r\nSubject: s\r\n\r\nCharged ".utf8)
    bodyBytes.append(0xA3)  // £ in ISO-8859-1; not valid UTF-8 on its own
    bodyBytes.append(contentsOf: Array("50.00\r\n".utf8))

    var reply = Array("* 1 FETCH (UID 12 BODY[] {\(bodyBytes.count)}\r\n".utf8)
    reply.append(contentsOf: bodyBytes)
    reply.append(contentsOf: Array(")\r\na003 OK FETCH completed\r\n".utf8))

    let channel = ScriptedChannel(
      rawReplies: [Array(loginOK.utf8), Array(examineOK.utf8), reply])
    let fetcher = NWIMAPFetcher(channel: channel, reader: NIOIMAPResponseReader())
    try await fetcher.connect(credentials)

    let messages = try await fetcher.fetch(uids: [12], in: "INBOX")

    let text = try XCTUnwrap(messages.first?.textBody)
    XCTAssertTrue(text.contains("£50.00"), "decoded as \(text)")
    XCTAssertFalse(text.contains("\u{FFFD}"), "lossy UTF-8 decode: \(text)")
  }

  /// §2.16, and the failure this whole layer is arranged to prevent: a server
  /// hanging up mid-fetch must not surface as a completed sync with fewer
  /// messages. It throws, the cursor stays put, the UIDs are re-fetched next
  /// sync, and the pipeline absorbs the repeat as a no-op.
  func testAByeMidFetchThrowsRatherThanReturningAShortBatch() async throws {
    let body = "From: <a@b.com>\r\n\r\none\r\n"
    let partial = "* 1 FETCH (UID 1 BODY[] {\(body.utf8.count)}\r\n" + body + ")\r\n"
      + "* BYE Server shutting down\r\n"

    let (fetcher, _) = try await connected(replies: [examineOK, partial])

    do {
      _ = try await fetcher.fetch(uids: [1, 2, 3], in: "INBOX")
      XCTFail("expected serverClosedMidCommand")
    } catch let error as IMAPTransportError {
      guard case .serverClosedMidCommand = error else {
        return XCTFail("expected serverClosedMidCommand, got \(error)")
      }
    }
  }

  /// The socket closing before the tagged completion is the same failure as a
  /// `* BYE` and gets the same answer — not an empty, successful batch.
  func testASocketClosingMidFetchAlsoThrows() async throws {
    let (fetcher, _) = try await connected(replies: [examineOK])

    do {
      _ = try await fetcher.fetch(uids: [1], in: "INBOX")
      XCTFail("expected serverClosedMidCommand")
    } catch let error as IMAPTransportError {
      guard case .serverClosedMidCommand = error else {
        return XCTFail("expected serverClosedMidCommand, got \(error)")
      }
    }
  }

  // MARK: - Serialization

  /// **Actors are reentrant, and this is the regression for it.** Every command
  /// is send-then-read-until-tagged, which suspends repeatedly; without the
  /// in-actor mutex a second call begins mid-command and the two commands'
  /// reads interleave on one socket. `IngestPipeline` failed on CI for exactly
  /// this shape.
  ///
  /// The assertion is on the operation log, not on the results: interleaving
  /// shows up as two sends with no read between them.
  func testConcurrentCommandsDoNotInterleaveOnTheSocket() async throws {
    let (fetcher, channel) = try await connected(replies: [
      examineOK,
      "* SEARCH 1 2\r\na003 OK SEARCH completed\r\n",
      "* SEARCH 3 4\r\na004 OK SEARCH completed\r\n",
    ])
    _ = try await fetcher.selectMailbox("INBOX")

    async let first = fetcher.uids(after: 0, in: "INBOX")
    async let second = fetcher.uids(after: 0, in: "INBOX")
    let results = try await [first, second]

    XCTAssertEqual(Set(results.flatMap { $0 }), [1, 2, 3, 4])

    var lastWasSend = false
    for operation in channel.operations {
      if case .send = operation {
        XCTAssertFalse(lastWasSend, "two commands were written back to back: \(channel.operations)")
        lastWasSend = true
      } else if case .receive = operation {
        lastWasSend = false
      }
    }
  }

  // MARK: - Disconnect

  func testDisconnectLogsOutThenClosesTheSocket() async throws {
    let (fetcher, channel) = try await connected(replies: ["a002 OK LOGOUT completed\r\n"])

    try await fetcher.disconnect()

    XCTAssertTrue(channel.sentText.hasSuffix("a002 LOGOUT\r\n"), channel.sentText)
    XCTAssertEqual(channel.operations.last, .close)
  }

  /// A server that has already gone still has to leave the socket released.
  /// Reporting a failure to disconnect helps nobody.
  func testDisconnectClosesEvenWhenLogoutFails() async throws {
    let (fetcher, channel) = try await connected(replies: [])

    try await fetcher.disconnect()

    XCTAssertEqual(channel.operations.last, .close)
  }
}

// MARK: - The real socket

/// The few paths through `NWConnectionChannel` that a test can actually reach.
///
/// **Everything else about this type is unverified and this unit's PR says so.**
/// A successful TLS handshake, LOGIN against Gmail, a real `UID FETCH` — none of
/// that is reachable from CI, and a green run here must not be read as a working
/// mailbox. That misreading is exactly what happened to U2b.
///
/// What these two do prove is real: the connection fails rather than hanging,
/// and the deadline in `perform(timeout:)` fires and cancels. A transport that
/// hangs forever on an unreachable server is the failure that leaves the sync
/// indicator spinning with nothing behind it.
final class NWConnectionChannelTests: XCTestCase {

  func testConnectingToAClosedPortFailsRatherThanHanging() async throws {
    let channel = NWConnectionChannel(timeouts: .init(connect: 5, read: 5, write: 5))
    let started = Date()

    // Port 1 on loopback: nothing listens there, so the OS refuses immediately
    // and `NWConnection` reports `.failed` rather than waiting.
    do {
      try await channel.open(host: "127.0.0.1", port: 1)
    } catch {
      // Any error is the pass — the assertion is that it *returned*, bounded.
      XCTAssertLessThan(Date().timeIntervalSince(started), 20)
      return
    }

    await channel.close()
    throw XCTSkip("something is listening on 127.0.0.1:1; cannot assert a refused connection")
  }

  /// A listener that accepts TCP and never speaks TLS. The handshake cannot
  /// complete, so without a deadline this call never returns — which is the
  /// whole reason `perform(timeout:)` exists.
  func testATLSHandshakeThatNeverCompletesHitsTheDeadline() async throws {
    let listener: NWListener
    do {
      listener = try NWListener(using: .tcp, on: .any)
    } catch {
      throw XCTSkip("cannot bind a loopback listener in this environment: \(error)")
    }

    // Accept connections and deliberately say nothing.
    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
    }
    listener.start(queue: .global())
    defer { listener.cancel() }

    // Give the listener a moment to acquire a port.
    for _ in 0..<50 where listener.port == nil {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    guard let port = listener.port else {
      throw XCTSkip("listener never reported a port")
    }

    let channel = NWConnectionChannel(timeouts: .init(connect: 2, read: 2, write: 2))
    let started = Date()

    do {
      try await channel.open(host: "127.0.0.1", port: Int(port.rawValue))
      await channel.close()
      XCTFail("a plain-TCP listener must not complete a TLS handshake")
    } catch {
      // Bounded, and bounded by *our* deadline rather than by luck.
      XCTAssertLessThan(Date().timeIntervalSince(started), 20, "the deadline did not fire")
    }
  }
}
