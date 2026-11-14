import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// A `MailFetching` that can fetch headers. It serves a fixed mailbox and records
/// every header and body fetch, so a test can see which bodies were asked for.
///
/// `fetchHeaders` returns what `RFC822Message` gives for a `HEADER.FIELDS (FROM)`
/// reply: the sender, an empty subject, the epoch date, and nil bodies.
final class HeaderFirstFetcher: MailFetching, @unchecked Sendable {
  let state: MailboxState
  private let messages: [MailMessage]

  private(set) var headerCalls: [[UInt32]] = []
  private(set) var fetched: [[UInt32]] = []

  init(
    messages: [MailMessage],
    state: MailboxState = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 999)
  ) {
    self.messages = messages
    self.state = state
  }

  var supportsHeaderFirstFetch: Bool { true }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  func selectMailbox(_ name: String) async throws -> MailboxState { state }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    messages.map(\.uid)
  }

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    messages.map(\.uid)
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    messages.map(\.uid).filter { $0 > uid }
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    fetched.append(uids)
    return messages.filter { uids.contains($0.uid) }
  }

  func fetchHeaders(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    headerCalls.append(uids)
    return messages.filter { uids.contains($0.uid) }.map {
      MailMessage(
        uid: $0.uid,
        uidValidity: $0.uidValidity,
        mailboxName: $0.mailboxName,
        fromRaw: $0.fromRaw,
        subject: "",
        headerDate: Date(timeIntervalSince1970: 0),
        htmlBody: nil,
        textBody: nil
      )
    }
  }
}

final class HeaderFirstSyncTests: XCTestCase {

  /// A copy of a fixture with a new UID and, optionally, a new sender.
  private func restamped(_ message: MailMessage, uid: UInt32, from: String? = nil) -> MailMessage {
    MailMessage(
      uid: uid,
      uidValidity: message.uidValidity,
      mailboxName: message.mailboxName,
      fromRaw: from ?? message.fromRaw,
      subject: message.subject,
      headerDate: message.headerDate,
      htmlBody: message.htmlBody,
      textBody: message.textBody
    )
  }

  /// UIDs 1-4. Two senders pass the domain gate (`hdfcbank.net`, `icicibank.com`);
  /// two do not (`newsletter.example`, which matches no bank token, and `unknown.org`).
  /// The non-admitted two carry debit text, so only the gate keeps them out.
  private func fourMessages() throws -> [MailMessage] {
    let hdfc = try MailFixtures.message("hdfc_debit_netbanking.eml", uid: 1)
    let icici = try MailFixtures.message("icici_debit_nested_split.eml", uid: 3)
    return [
      restamped(hdfc, uid: 1, from: "HDFC Bank Alerts <alerts@hdfcbank.net>"),
      restamped(hdfc, uid: 2, from: "Deals <news@newsletter.example>"),
      restamped(icici, uid: 3, from: "ICICI Bank <alerts@icicibank.com>"),
      restamped(hdfc, uid: 4, from: "Shop <bot@unknown.org>"),
    ]
  }

  // MARK: - Only admitted senders are fetched in full

  func testOnlyAdmittedSendersAreBodyFetched() async throws {
    let fetcher = HeaderFirstFetcher(messages: try fourMessages())

    _ = try await MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline()).syncNow()

    XCTAssertEqual(fetcher.headerCalls, [[1, 2, 3, 4]], "every UID gets a header fetch")
    XCTAssertEqual(fetcher.fetched, [[1, 3]], "only the admitted senders get a body")
  }

  // MARK: - Same counts as the body-first path

  func testSummaryMatchesTheBodyFirstPath() async throws {
    let messages = try fourMessages()

    let bodyFirstPipeline = RecordingPipeline()
    bodyFirstPipeline.result = IngestBatchResult(created: 2, merged: 0, flagged: 0)
    let bodyFirst = try await MailSyncEngine(
      fetcher: StubFetcher(messages: messages), pipeline: bodyFirstPipeline
    ).syncNow()

    let headerFirstPipeline = RecordingPipeline()
    headerFirstPipeline.result = IngestBatchResult(created: 2, merged: 0, flagged: 0)
    let headerFirst = try await MailSyncEngine(
      fetcher: HeaderFirstFetcher(messages: messages), pipeline: headerFirstPipeline
    ).syncNow()

    XCTAssertEqual(headerFirst.scanned, bodyFirst.scanned)
    XCTAssertEqual(headerFirst.created, bodyFirst.created)
    XCTAssertEqual(headerFirst.merged, bodyFirst.merged)
    XCTAssertEqual(headerFirst.flagged, bodyFirst.flagged)
    XCTAssertEqual(headerFirst.packMatched, bodyFirst.packMatched)
    XCTAssertEqual(headerFirst.heuristicMatched, bodyFirst.heuristicMatched)
    XCTAssertEqual(headerFirst.unmatchedSenders, bodyFirst.unmatchedSenders)

    // The drafts themselves, not only their count: same amounts, same order.
    let bodyFirstAmounts = bodyFirstPipeline.received.flatMap { $0.map(\.amountMinor) }
    let headerFirstAmounts = headerFirstPipeline.received.flatMap { $0.map(\.amountMinor) }
    XCTAssertFalse(bodyFirstAmounts.isEmpty, "the fixture must produce drafts")
    XCTAssertEqual(headerFirstAmounts, bodyFirstAmounts)
  }

  // MARK: - A batch with nothing admitted reads no bodies

  func testABatchWithNoAdmittedSenderFetchesNoBodies() async throws {
    let rejected = try fourMessages().filter { ["unknown.org", "newsletter.example"].contains($0.senderDomain) }
    let fetcher = HeaderFirstFetcher(messages: rejected)
    let pipeline = RecordingPipeline()

    let summary = try await MailSyncEngine(fetcher: fetcher, pipeline: pipeline).syncNow()

    XCTAssertEqual(fetcher.fetched, [], "no body is asked for when no sender passes")
    XCTAssertEqual(summary.scanned, 2, "the headers were still examined")
    XCTAssertEqual(summary.packMatched + summary.heuristicMatched, 0)
    XCTAssertTrue(pipeline.received.isEmpty)
  }
}
