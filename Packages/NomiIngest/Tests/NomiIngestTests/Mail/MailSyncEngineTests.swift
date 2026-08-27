import Foundation
import NomiCore
import XCTest

@testable import NomiIngest

/// A `MailFetching` that serves a fixed set of messages and records what was
/// asked of it. Everything below the transport seam is unreachable from CI, so
/// this is where the tested part stops.
final class StubFetcher: MailFetching, @unchecked Sendable {
  private let messages: [MailMessage]
  let state: MailboxState

  private(set) var uidsAfterCalls: [UInt32] = []
  private(set) var uidsSinceCalls: [Date] = []
  private(set) var fetched: [[UInt32]] = []

  init(
    messages: [MailMessage],
    state: MailboxState = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 999)
  ) {
    self.messages = messages
    self.state = state
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}

  func selectMailbox(_ name: String) async throws -> MailboxState { state }

  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] {
    uidsSinceCalls.append(date)
    return messages.map(\.uid)
  }

  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    uidsAfterCalls.append(uid)
    return messages.map(\.uid).filter { $0 > uid }
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    fetched.append(uids)
    return messages.filter { uids.contains($0.uid) }
  }
}

final class RecordingPipeline: DraftIngesting, @unchecked Sendable {
  private(set) var received: [[TransactionDraft]] = []
  var result = IngestBatchResult(created: 0, merged: 0, flagged: 0)

  func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    received.append(drafts)
    return result
  }
}

/// A fetcher whose `fetch` fails, standing in for a server that hangs up
/// mid-FETCH (an unexpected `* BYE` before the tagged completion).
final class FailingFetchFetcher: MailFetching, @unchecked Sendable {
  let state: MailboxState
  private let uids: [UInt32]
  private(set) var fetchAttempts = 0

  init(
    uids: [UInt32],
    state: MailboxState = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 999)
  ) {
    self.uids = uids
    self.state = state
  }

  struct Hangup: Error {}

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  func selectMailbox(_ name: String) async throws -> MailboxState { state }
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] { uids }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    uids.filter { $0 > uid }
  }
  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    fetchAttempts += 1
    throw Hangup()
  }
}

final class MailSyncEngineTests: XCTestCase {

  private func message(_ file: String, uid: UInt32) throws -> MailMessage {
    try MailFixtures.message(file, uid: uid)
  }

  // MARK: - Counters

  func testTheSummaryReportsWhatThePipelineDidAndWhichLayerReadEach() async throws {
    let messages = [
      try message("hdfc_debit_netbanking.eml", uid: 10),
      try message("kotak_debit_card.eml", uid: 11),
      try message("unknown_bank_layer2.eml", uid: 12),
      try message("promo_sbi_fd.eml", uid: 13),
    ]
    let pipeline = RecordingPipeline()
    pipeline.result = IngestBatchResult(created: 3, merged: 0, flagged: 3)

    let summary = try await MailSyncEngine(
      fetcher: StubFetcher(messages: messages), pipeline: pipeline
    ).syncNow()

    XCTAssertEqual(summary.scanned, 4)
    XCTAssertEqual(summary.packMatched, 2)
    XCTAssertEqual(summary.heuristicMatched, 1)
    // created/merged/flagged are the PIPELINE's numbers, not this engine's — it
    // never writes a Transaction.
    XCTAssertEqual(summary.created, 3)
    XCTAssertEqual(summary.flagged, 3)
    // The promo produced no draft, so only three reached the pipeline.
    XCTAssertEqual(pipeline.received.first?.count, 3)
  }

  func testThePromotionalMessageIsScannedButNeverIngested() async throws {
    let pipeline = RecordingPipeline()
    let messages = [try message("promo_hdfc_cashback.eml", uid: 5)]

    let summary = try await MailSyncEngine(
      fetcher: StubFetcher(messages: messages), pipeline: pipeline
    ).syncNow()

    XCTAssertEqual(summary.scanned, 1)
    XCTAssertEqual(summary.packMatched, 0)
    XCTAssertEqual(summary.heuristicMatched, 0)
    XCTAssertTrue(pipeline.received.isEmpty, "no drafts means no pipeline call at all")
  }

  // MARK: - Incremental sync

  func testTheFirstSyncScansEverythingAndThenTheCursorAdvances() async throws {
    let messages = [
      try message("axis_debit_atm.eml", uid: 40),
      try message("axis_credit_interest.eml", uid: 41),
    ]
    let fetcher = StubFetcher(messages: messages)
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline())

    _ = try await engine.syncNow()

    let cursor = try XCTUnwrap(await engine.cursor)
    XCTAssertEqual(cursor.lastSeenUID, 41)
    XCTAssertEqual(cursor.uidValidity, 900_100)
    XCTAssertEqual(fetcher.uidsAfterCalls, [], "no cursor yet, so no incremental search")
  }

  func testASecondSyncSearchesOnlyAboveTheCursor() async throws {
    let messages = [try message("axis_debit_atm.eml", uid: 40)]
    let fetcher = StubFetcher(messages: messages)
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 900_100, lastSeenUID: 39)
    )

    _ = try await engine.syncNow()

    XCTAssertEqual(fetcher.uidsAfterCalls, [39])
    XCTAssertEqual(fetcher.fetched, [[40]])
  }

  /// A UIDVALIDITY change makes every stored UID meaningless. Rescanning
  /// re-ingests, which the pipeline's exact-key dedupe absorbs; skipping would
  /// lose transactions with no signal that it happened.
  func testAUIDValidityChangeRescansInsteadOfSkipping() async throws {
    let messages = [try message("axis_debit_atm.eml", uid: 40)]
    let fetcher = StubFetcher(
      messages: messages,
      state: MailboxState(name: "INBOX", uidValidity: 777_777, uidNext: 999))
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 900_100, lastSeenUID: 39)
    )

    _ = try await engine.syncNow()

    XCTAssertEqual(fetcher.uidsAfterCalls, [], "must not trust the old cursor")
    XCTAssertEqual(fetcher.uidsSinceCalls.count, 1)
    XCTAssertEqual(try XCTUnwrap(await engine.cursor).uidValidity, 777_777)
  }

  func testAnEmptyMailboxProducesAnEmptySummaryAndNoPipelineCall() async throws {
    let pipeline = RecordingPipeline()
    let summary = try await MailSyncEngine(
      fetcher: StubFetcher(messages: []), pipeline: pipeline
    ).syncNow()

    XCTAssertEqual(summary.scanned, 0)
    XCTAssertTrue(summary.unmatchedSenders.isEmpty)
    XCTAssertTrue(pipeline.received.isEmpty)
  }

  // MARK: - Backfill

  func testBackfillSearchesFromSixMonthsBack() async throws {
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let fetcher = StubFetcher(messages: [])
    let engine = MailSyncEngine(
      fetcher: fetcher, pipeline: RecordingPipeline(), now: { now })

    _ = try await engine.backfill(months: 6)

    let since = try XCTUnwrap(fetcher.uidsSinceCalls.first)
    let months = Calendar(identifier: .gregorian)
      .dateComponents([.month], from: since, to: now).month
    XCTAssertEqual(months, 6)
  }
  // MARK: - A hangup mid-fetch must not look like "nothing new"

  /// If the fetch fails, the cursor stays where it was and the same UIDs are
  /// re-fetched next sync.
  ///
  /// This is the mechanism behind U2b's `* BYE` handling (§2.16). A server that
  /// hangs up mid-FETCH would otherwise be indistinguishable from "0 new
  /// transactions" — the silent-zero failure that is worth more than any amount
  /// of tidy error handling to avoid. Re-fetching is safe: re-ingesting a
  /// `SourceRef` the pipeline already has is a total no-op.
  func testAFailedFetchLeavesTheCursorWhereItWasAndRethrows() async throws {
    let fetcher = FailingFetchFetcher(uids: [40, 41])
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 900_100, lastSeenUID: 39)
    )

    do {
      _ = try await engine.syncNow()
      XCTFail("syncNow should have rethrown the fetch failure")
    } catch is FailingFetchFetcher.Hangup {
      // expected
    }

    let cursor = try XCTUnwrap(await engine.cursor)
    XCTAssertEqual(cursor.lastSeenUID, 39, "the cursor must not advance past an unfetched UID")
  }

  func testTheSameUIDsAreRetriedOnTheNextSyncAfterAFailure() async throws {
    let fetcher = FailingFetchFetcher(uids: [40, 41])
    let engine = MailSyncEngine(
      fetcher: fetcher,
      pipeline: RecordingPipeline(),
      cursor: MailSyncCursor(mailbox: "INBOX", uidValidity: 900_100, lastSeenUID: 39)
    )

    _ = try? await engine.syncNow()
    _ = try? await engine.syncNow()

    XCTAssertEqual(fetcher.fetchAttempts, 2, "the second sync must re-attempt the same UIDs")
  }

  /// A failed fetch must not reach the pipeline at all — no partial batch, no
  /// half-ingested sync.
  func testAFailedFetchIngestsNothing() async throws {
    let pipeline = RecordingPipeline()
    let engine = MailSyncEngine(fetcher: FailingFetchFetcher(uids: [40]), pipeline: pipeline)

    _ = try? await engine.syncNow()

    XCTAssertTrue(pipeline.received.isEmpty)
  }
}
