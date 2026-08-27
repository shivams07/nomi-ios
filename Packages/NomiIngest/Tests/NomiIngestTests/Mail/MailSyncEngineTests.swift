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
  private(set) var windowCalls: [MailSyncEngine.SearchWindow] = []
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

  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    windowCalls.append(MailSyncEngine.SearchWindow(since: since, before: before))
    // Every window returns everything, so the engine's dedupe is exercised
    // rather than assumed: six windows over the same four messages must still
    // fetch each UID once.
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
  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] { uids }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    uids.filter { $0 > uid }
  }
  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    fetchAttempts += 1
    throw Hangup()
  }
}

/// A mailbox of arbitrary size, built by stamping fresh UIDs on one fixture, and
/// able to hang up on the Nth `fetch`.
///
/// The point of it is the shape of the calls, not the mail: how many fetches,
/// how big, in what order, and what the cursor did when one of them threw.
final class BatchingFetcher: MailFetching, @unchecked Sendable {
  let state: MailboxState
  private let template: MailMessage
  /// Returned from every search **in this order** — deliberately not sorted, so
  /// the engine's own sort is what makes the batches ascending.
  private let searchOrder: [UInt32]
  private let failOnFetchCall: Int?

  private(set) var fetched: [[UInt32]] = []
  private(set) var windowCalls: [MailSyncEngine.SearchWindow] = []

  struct Hangup: Error {}

  init(
    uids: [UInt32],
    template: MailMessage,
    failOnFetchCall: Int? = nil,
    state: MailboxState = MailboxState(name: "INBOX", uidValidity: 900_100, uidNext: 99_999)
  ) {
    self.searchOrder = uids
    self.template = template
    self.failOnFetchCall = failOnFetchCall
    self.state = state
  }

  func connect(_ credentials: IMAPCredentials) async throws {}
  func disconnect() async throws {}
  func selectMailbox(_ name: String) async throws -> MailboxState { state }
  func uids(since date: Date, in mailbox: String) async throws -> [UInt32] { searchOrder }
  func uids(after uid: UInt32, in mailbox: String) async throws -> [UInt32] {
    searchOrder.filter { $0 > uid }
  }

  /// Only the first window returns anything. A backfill that asked one question
  /// and one that asked six must both end up fetching the same set once.
  func uids(since: Date, before: Date, in mailbox: String) async throws -> [UInt32] {
    windowCalls.append(MailSyncEngine.SearchWindow(since: since, before: before))
    return windowCalls.count == 1 ? searchOrder : []
  }

  func fetch(uids: [UInt32], in mailbox: String) async throws -> [MailMessage] {
    fetched.append(uids)
    if fetched.count == failOnFetchCall { throw Hangup() }
    return uids.map {
      MailMessage(
        uid: $0,
        uidValidity: template.uidValidity,
        mailboxName: template.mailboxName,
        fromRaw: template.fromRaw,
        subject: template.subject,
        headerDate: template.headerDate,
        htmlBody: template.htmlBody,
        textBody: template.textBody
      )
    }
  }
}

/// Collects `BackfillProgress` ticks from the engine's callback.
final class ProgressLog: @unchecked Sendable {
  private let lock = NSLock()
  private var ticks: [BackfillProgress] = []

  var recorded: [BackfillProgress] {
    lock.lock()
    defer { lock.unlock() }
    return ticks
  }

  var callback: @Sendable (BackfillProgress) -> Void {
    { [self] tick in
      lock.lock()
      ticks.append(tick)
      lock.unlock()
    }
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

    let loaded = await engine.cursor
    let cursor = try XCTUnwrap(loaded)
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
    let loaded = await engine.cursor
    XCTAssertEqual(try XCTUnwrap(loaded).uidValidity, 777_777)
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

    // Six windows, not one search (§2.17), and the oldest still reaches back six
    // months — the window walk changed the number of requests, not the horizon.
    XCTAssertEqual(fetcher.windowCalls.count, 6)
    XCTAssertTrue(fetcher.uidsSinceCalls.isEmpty, "the backfill must not use the unwindowed search")

    let since = try XCTUnwrap(fetcher.windowCalls.first?.since)
    let months = Calendar(identifier: .gregorian)
      .dateComponents([.month], from: since, to: now).month
    XCTAssertEqual(months, 6)
  }

  /// The windows must cover the whole span with no hole in it. A hole loses
  /// transactions silently, which is the one failure mode here that nobody would
  /// ever notice (§2.17).
  func testTheWindowsTileTheWholeSpanAndOverlapRatherThanRiskAGap() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_787_000_000)
    let windows = MailSyncEngine.monthlyWindows(months: 6, endingAt: now)

    XCTAssertEqual(windows.count, 6)

    for (earlier, later) in zip(windows, windows.dropFirst()) {
      XCTAssertLessThan(
        later.since, earlier.before,
        "adjacent windows must overlap: dedupe absorbs a duplicate, nothing recovers a lost day")
      XCTAssertLessThan(earlier.since, earlier.before, "a window must be non-empty")
    }

    // BEFORE is exclusive and date-granular, so the last window has to run to
    // tomorrow or mail that arrived today is missed on the run that goes looking
    // for it.
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    XCTAssertEqual(windows.last?.before, tomorrow)
  }

  func testAZeroMonthBackfillStillAsksForOneWindowRatherThanNone() {
    XCTAssertEqual(
      MailSyncEngine.monthlyWindows(months: 0, endingAt: Date()).count, 1,
      "months <= 0 is a caller error; scanning today beats scanning nothing")
  }

  // MARK: - Batching (§2.17)

  private func template() throws -> MailMessage {
    try message("hdfc_debit_netbanking.eml", uid: 1)
  }

  /// The fix itself: 250 UIDs must not become one `UID FETCH` holding 250 HTML
  /// bodies in memory. At 50 KB a message that is the 150 MB first run iOS kills.
  func testABackfillFetchesInBatchesRatherThanAllAtOnce() async throws {
    let uids = Array(UInt32(100)...UInt32(349))
    let fetcher = BatchingFetcher(uids: uids, template: try template())
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline())

    _ = try await engine.backfill(months: 6, onProgress: nil)

    XCTAssertEqual(fetcher.fetched.count, 5, "250 UIDs at a batch size of 50")
    XCTAssertTrue(fetcher.fetched.allSatisfy { $0.count <= MailSyncEngine.fetchBatchSize })
    XCTAssertEqual(fetcher.fetched.flatMap { $0 }, uids, "every UID exactly once, in order")
  }

  /// A server may return SEARCH results in any order it likes. The cursor's
  /// "completed prefix" only means something if the batches ascend, so the
  /// engine sorts rather than trusting the wire.
  func testTheEngineSortsBeforeBatchingSoTheBatchesAscend() async throws {
    let shuffled: [UInt32] = [300, 120, 349, 100, 275, 101, 200]
    let fetcher = BatchingFetcher(uids: shuffled, template: try template())
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline())

    _ = try await engine.backfill(months: 6, onProgress: nil)

    XCTAssertEqual(fetcher.fetched, [[100, 101, 120, 200, 275, 300, 349]])
  }

  /// `BackfillProgress` exists so U7's banner can show something moving. Before
  /// batching, the only value the engine could produce was one final tick after
  /// all the work — which is not progress, and left U2b unable to satisfy its own
  /// contract (§2.17).
  func testABackfillEmitsProgressPerBatchAndReachesItsTotal() async throws {
    let uids = Array(UInt32(100)...UInt32(349))
    let pipeline = RecordingPipeline()
    pipeline.result = IngestBatchResult(created: 2, merged: 0, flagged: 0)
    let log = ProgressLog()
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(uids: uids, template: try template()), pipeline: pipeline)

    _ = try await engine.backfill(months: 6, onProgress: log.callback)

    let ticks = log.recorded
    // One tick announcing the total as soon as the search is done, then one per
    // completed batch.
    XCTAssertEqual(ticks.count, 6)
    XCTAssertEqual(ticks.first?.scanned, 0)
    XCTAssertTrue(ticks.allSatisfy { $0.total == 250 }, "the total must not move mid-run")
    XCTAssertEqual(ticks.dropFirst().map(\.scanned), [50, 100, 150, 200, 250])
    XCTAssertEqual(ticks.dropFirst().map(\.created), [2, 4, 6, 8, 10])
    XCTAssertEqual(ticks.last?.scanned, ticks.last?.total, "a bar that stops at 94% is a bug report")
  }

  /// The acceptance criterion, verbatim: batch 3 of 5 throws, and the cursor has
  /// advanced to the end of batch 2 and no further.
  ///
  /// This is what makes a failed backfill resumable instead of wasted. Every
  /// message in batches 1 and 2 is already through the pipeline; re-fetching
  /// batch 3 next run costs one round trip, and re-ingesting anything from
  /// batches 1–2 would be a no-op anyway.
  func testWhenTheThirdBatchFailsTheCursorSitsAtTheEndOfTheSecond() async throws {
    let uids = Array(UInt32(100)...UInt32(349))
    let pipeline = RecordingPipeline()
    let fetcher = BatchingFetcher(uids: uids, template: try template(), failOnFetchCall: 3)
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: pipeline)

    do {
      _ = try await engine.backfill(months: 6, onProgress: nil)
      XCTFail("the backfill must rethrow the hangup, not report a short sync")
    } catch is BatchingFetcher.Hangup {
      // expected
    }

    let loaded = await engine.cursor
    let cursor = try XCTUnwrap(loaded)
    XCTAssertEqual(cursor.lastSeenUID, 199, "end of batch 2 — UIDs 150...199")
    XCTAssertEqual(fetcher.fetched.count, 3, "it must stop at the failure, not carry on")
    XCTAssertEqual(pipeline.received.count, 2, "batch 3 reached the pipeline zero times")
  }

  /// A failure mid-backfill keeps the work already done. The counterpart to the
  /// test above: the second attempt starts where the first stopped.
  func testTheRetryAfterAFailedBatchResumesRatherThanRestarts() async throws {
    let uids = Array(UInt32(100)...UInt32(349))
    let fixture = try template()
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(uids: uids, template: fixture, failOnFetchCall: 3),
      pipeline: RecordingPipeline())

    _ = try? await engine.backfill(months: 6, onProgress: nil)

    let resumed = BatchingFetcher(uids: uids, template: fixture)
    let second = MailSyncEngine(
      fetcher: resumed, pipeline: RecordingPipeline(), cursor: await engine.cursor)
    _ = try await second.syncNow()

    XCTAssertEqual(
      resumed.fetched.flatMap { $0 }.first, 200,
      "the resume must start at batch 3, not re-scan batches 1 and 2")
  }

  /// Counters are sums across batches, not the last batch's numbers.
  func testTheSummaryTotalsEveryBatchRatherThanTheLastOne() async throws {
    let pipeline = RecordingPipeline()
    pipeline.result = IngestBatchResult(created: 3, merged: 1, flagged: 2)
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(
        uids: Array(UInt32(100)...UInt32(249)), template: try template()),
      pipeline: pipeline)

    let summary = try await engine.backfill(months: 6, onProgress: nil)

    XCTAssertEqual(summary.scanned, 150)
    XCTAssertEqual(summary.packMatched, 150)
    XCTAssertEqual(summary.created, 9, "3 batches x 3")
    XCTAssertEqual(summary.merged, 3)
    XCTAssertEqual(summary.flagged, 6)
  }

  /// `unmatchedSenders` is the deliverable that replaced asking Shivam which
  /// banks he uses (§2.5.1), and it now has to survive being counted 60 batches
  /// at a time.
  func testUnmatchedSenderCountsAreSummedAcrossBatches() async throws {
    let engine = MailSyncEngine(
      fetcher: BatchingFetcher(
        uids: Array(UInt32(100)...UInt32(219)),
        template: try message("unknown_bank_layer2.eml", uid: 1)),
      pipeline: RecordingPipeline())

    let summary = try await engine.backfill(months: 6, onProgress: nil)

    XCTAssertEqual(summary.heuristicMatched, 120)
    XCTAssertEqual(summary.unmatchedSenders.count, 1)
    XCTAssertEqual(
      summary.unmatchedSenders.first?.count, 120,
      "120 across three batches (50 + 50 + 20), summed — not the last batch's 20")
  }

  /// The merge has to happen at the counts, not at two `top()` lists.
  ///
  /// A domain sitting eleventh in one batch and first overall is exactly what
  /// `unmatchedSenders` is for — the bank whose mail is spread thinly across six
  /// months. Reducing each batch through its own top-10 first would drop it from
  /// the batch where it was quiet and undercount it everywhere else.
  func testTheTallyMergesCountsNotTruncatedTopTens() {
    func tally(_ domains: [String: Int]) -> UnmatchedSenderTally {
      var tally = UnmatchedSenderTally()
      for (domain, count) in domains {
        for index in 0..<count {
          tally.record(
            MailMessage(
              uid: UInt32(index), uidValidity: 1, fromRaw: "Alerts <alerts@\(domain)>",
              subject: "", headerDate: Date(), htmlBody: nil, textBody: nil))
        }
      }
      return tally
    }

    var loud: [String: Int] = [:]
    for index in 1...10 { loud["bank\(index).example"] = 3 }

    var merged = tally(loud.merging(["quiet.example": 1]) { first, _ in first })
    merged.merge(tally(["quiet.example": 5]))

    let top = merged.top()
    XCTAssertEqual(top.first?.domain, "quiet.example")
    XCTAssertEqual(top.first?.count, 6, "1 from the batch where it ranked eleventh, plus 5")
  }

  /// Six windows over the same mailbox must not fetch anything twice. Windows
  /// overlap by a day on purpose, so this is load-bearing rather than tidy.
  func testOverlappingWindowsDoNotFetchTheSameUIDTwice() async throws {
    let messages = [
      try message("axis_debit_atm.eml", uid: 40),
      try message("axis_credit_interest.eml", uid: 41),
    ]
    // StubFetcher returns every UID from every window — six windows, two UIDs.
    let fetcher = StubFetcher(messages: messages)
    let engine = MailSyncEngine(fetcher: fetcher, pipeline: RecordingPipeline())

    let summary = try await engine.backfill(months: 6, onProgress: nil)

    XCTAssertEqual(fetcher.windowCalls.count, 6)
    XCTAssertEqual(fetcher.fetched, [[40, 41]])
    XCTAssertEqual(summary.scanned, 2)
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

    let loaded = await engine.cursor
    let cursor = try XCTUnwrap(loaded)
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
