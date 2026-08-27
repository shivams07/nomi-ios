import Foundation
import NomiCore

/// Fetch, pre-filter, extract, hand to the pipeline, count.
///
/// It never writes a `Transaction` — U4's pipeline is the single write path, and
/// this engine's only output besides drafts is the `SyncSummary`.
///
/// **The work is chunked, and that is not an optimisation** (§2.17). Fetching
/// every UID a six-month backfill returns in one call holds every HTML body in
/// memory at once: 3,000 messages at a conservative 50 KB each is 150 MB
/// resident on a phone during the app's first run, which iOS kills. It also
/// makes `BackfillProgress` impossible to emit honestly — one await that returns
/// everything can only report progress after the work is finished.
public actor MailSyncEngine {
  private let fetcher: any MailFetching
  private let extractor: MailTransactionExtractor
  private let pipeline: any DraftIngesting
  private let mailboxName: String
  private let now: @Sendable () -> Date

  /// UIDs per `UID FETCH`.
  ///
  /// 50 messages of bank HTML is a few MB resident at a time — the bound that
  /// matters. Smaller would mean more round trips on a connection whose latency
  /// dominates; larger walks back toward the problem this exists to solve. It is
  /// a memory ceiling, not a tuned number.
  public static let fetchBatchSize = 50

  /// Advanced only after a batch has been fetched AND handed to the pipeline,
  /// and only as far as the **completed prefix** — never past a UID whose batch
  /// threw. If ingestion fails halfway through a backfill, every completed batch
  /// is kept and the resume costs one re-fetched batch, because re-ingesting an
  /// identical `SourceRef` is a total no-op in U4, not a duplicate row.
  ///
  /// The prefix only means anything because the UIDs are sorted ascending before
  /// they are sliced. That sort is load-bearing.
  public private(set) var cursor: MailSyncCursor?

  public init(
    fetcher: any MailFetching,
    pipeline: any DraftIngesting,
    extractor: MailTransactionExtractor = MailTransactionExtractor(),
    mailboxName: String = "INBOX",
    cursor: MailSyncCursor? = nil,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.fetcher = fetcher
    self.pipeline = pipeline
    self.extractor = extractor
    self.mailboxName = mailboxName
    self.cursor = cursor
    self.now = now
  }

  /// Incremental: everything with a UID above the cursor.
  ///
  /// A UIDVALIDITY change invalidates every stored UID, so the mailbox is
  /// rescanned from the start rather than silently skipping mail. The cost is a
  /// re-ingest that the pipeline's exact-key dedupe absorbs; the alternative is
  /// losing transactions with no signal that it happened.
  ///
  /// **That rescan is the one remaining unwindowed SEARCH.** `SINCE 1970` over a
  /// whole mailbox returns every UID on one line, and windowing it by month
  /// would mean walking from whenever the account was opened — which is not
  /// obviously better. It is bounded by the framer's 256 KB line ceiling
  /// (§2.17), and it is rare: UIDVALIDITY changing at all is a server-side event
  /// most mailboxes never see. Flagged rather than silently decided.
  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    let state = try await fetcher.selectMailbox(mailboxName)

    let uids: [UInt32]
    if let cursor, cursor.uidValidity == state.uidValidity, cursor.mailbox == mailboxName {
      uids = try await fetcher.uids(after: cursor.lastSeenUID, in: mailboxName)
    } else {
      uids = try await fetcher.uids(since: Date(timeIntervalSince1970: 0), in: mailboxName)
    }

    return try await process(uids: uids, state: state, onProgress: nil)
  }

  /// The first run: six months back (§1.3, R11). This is also the run that
  /// produces `unmatchedSenders` — the measurement that tells us which banks the
  /// user actually has, computed on their own device (§2.5.1).
  ///
  /// The search is walked **one month at a time** rather than asked in one go
  /// (§2.17 axis 2). A `UID SEARCH` reply is a single line with no CRLF until
  /// the end, so six months of a busy mailbox — 15,000 UIDs at 7 digits — is
  /// ~120 KB on that line. Windowing bounds the response by construction instead
  /// of by a ceiling we guessed at.
  ///
  /// `onProgress` fires once with the total as soon as the search is done, then
  /// once per completed batch. It is what U2b's `backfillProgress` stream is
  /// made of; passing `nil` costs nothing.
  @discardableResult
  public func backfill(
    months: Int,
    onProgress: (@Sendable (BackfillProgress) -> Void)? = nil
  ) async throws -> SyncSummary {
    let state = try await fetcher.selectMailbox(mailboxName)

    var found = Set<UInt32>()
    for window in Self.monthlyWindows(months: months, endingAt: now()) {
      let uids = try await fetcher.uids(
        since: window.since, before: window.before, in: mailboxName)
      found.formUnion(uids)
    }

    return try await process(uids: found.sorted(), state: state, onProgress: onProgress)
  }

  // MARK: - Search windows

  /// One `SINCE`/`BEFORE` pair. `SINCE` is inclusive, `BEFORE` is exclusive,
  /// both are date-granular in IMAP — the time of day is discarded by the
  /// server.
  struct SearchWindow: Equatable, Sendable {
    let since: Date
    let before: Date
  }

  /// `months` windows walking back from `end`, newest last.
  ///
  /// Two deliberate distortions, both in the direction the design specifies —
  /// **err toward overlap, because dedupe absorbs a duplicate and nothing
  /// recovers a dropped day** (§2.17):
  ///
  /// 1. Each window starts one day *before* the previous one ended. Adjacent
  ///    `SINCE d1 BEFORE d2` / `SINCE d2 BEFORE d3` windows tile exactly on
  ///    paper, but the server applies those dates in *its* timezone against the
  ///    message's INTERNALDATE, and we do not know that timezone. A day of slack
  ///    costs a re-fetch the pipeline no-ops away.
  /// 2. The last window ends *tomorrow*, not today, because `BEFORE` is
  ///    exclusive and date-granular: `BEFORE <today>` omits everything that
  ///    arrived today, which on a first run is exactly the mail the user is
  ///    looking at while they wait.
  static func monthlyWindows(
    months: Int,
    endingAt end: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) -> [SearchWindow] {
    let span = max(months, 1)
    let today = calendar.startOfDay(for: end)

    var boundaries: [Date] = (0...span).map { offset in
      calendar.date(byAdding: .month, value: -(span - offset), to: today) ?? today
    }
    boundaries[span] = calendar.date(byAdding: .day, value: 1, to: today) ?? today

    return (0..<span).map { index in
      let start = boundaries[index]
      return SearchWindow(
        since: calendar.date(byAdding: .day, value: -1, to: start) ?? start,
        before: boundaries[index + 1]
      )
    }
  }

  // MARK: - Batched processing

  private func process(
    uids: [UInt32],
    state: MailboxState,
    onProgress: (@Sendable (BackfillProgress) -> Void)?
  ) async throws -> SyncSummary {
    // Sorted here rather than trusted from the caller: the cursor advances to
    // the end of each completed batch, which is only correct if the batches are
    // in ascending order. A server is free to return SEARCH results in any
    // order it likes.
    let ordered = uids.sorted()

    guard !ordered.isEmpty else {
      cursor = MailSyncCursor(
        mailbox: mailboxName, uidValidity: state.uidValidity,
        lastSeenUID: cursor?.lastSeenUID ?? 0)
      onProgress?(BackfillProgress(scanned: 0, total: 0, created: 0))
      return Self.emptySummary
    }

    onProgress?(BackfillProgress(scanned: 0, total: ordered.count, created: 0))

    var totals = Totals()

    for batch in ordered.slices(of: Self.fetchBatchSize) {
      let messages = try await fetcher.fetch(uids: batch, in: mailboxName)
      let outcome = classify(messages)

      let ingested = outcome.drafts.isEmpty
        ? IngestBatchResult.empty
        : try await pipeline.ingest(outcome.drafts)

      totals.add(messages: messages.count, outcome: outcome, ingested: ingested)

      // Only now, and only to the end of this batch. Everything above it in
      // `ordered` is still unfetched.
      cursor = MailSyncCursor(
        mailbox: mailboxName,
        uidValidity: state.uidValidity,
        lastSeenUID: max(batch.last ?? 0, cursor?.lastSeenUID ?? 0)
      )

      // `attempted`, not `scanned`: a UID can vanish between the SEARCH and the
      // FETCH, and a progress bar that stops at 94% because four messages were
      // deleted is a bug report. `SyncSummary.scanned` keeps its own meaning —
      // messages actually read.
      totals.attempted += batch.count
      onProgress?(
        BackfillProgress(
          scanned: totals.attempted, total: ordered.count, created: totals.created))
    }

    return totals.summary()
  }

  /// Running counters across batches. Kept out of `process` so the merge rules
  /// live in one place — in particular the tally, which must be merged as counts
  /// and not as two truncated top-10 lists.
  private struct Totals {
    var attempted = 0
    var scanned = 0
    var created = 0
    var merged = 0
    var flagged = 0
    var packMatched = 0
    var heuristicMatched = 0
    var tally = UnmatchedSenderTally()

    mutating func add(messages: Int, outcome: Classification, ingested: IngestBatchResult) {
      scanned += messages
      created += ingested.created
      merged += ingested.merged
      flagged += ingested.flagged
      packMatched += outcome.packMatched
      heuristicMatched += outcome.heuristicMatched
      tally.merge(outcome.tally)
    }

    func summary() -> SyncSummary {
      SyncSummary(
        scanned: scanned, created: created, merged: merged, flagged: flagged,
        packMatched: packMatched, heuristicMatched: heuristicMatched,
        unmatchedSenders: tally.top()
      )
    }
  }

  struct Classification: Sendable {
    var drafts: [TransactionDraft] = []
    var packMatched = 0
    var heuristicMatched = 0
    var tally = UnmatchedSenderTally()
  }

  /// Pure, and separated out so the counters can be asserted against fixtures
  /// with no pipeline and no transport in the way.
  nonisolated func classify(_ messages: [MailMessage]) -> Classification {
    var result = Classification()

    for message in messages {
      let outcome = extractor.outcome(for: message)
      guard let draft = outcome.draft, let layer = outcome.layer else { continue }

      result.drafts.append(draft)
      switch layer {
      case .pack:
        result.packMatched += 1
      case .heuristic:
        result.heuristicMatched += 1
        // Domain only. This is the deliverable that replaced the question.
        result.tally.record(message)
      }
    }
    return result
  }

  private static let emptySummary = SyncSummary(
    scanned: 0, created: 0, merged: 0, flagged: 0,
    packMatched: 0, heuristicMatched: 0, unmatchedSenders: []
  )
}

extension Array {
  /// Consecutive slices of at most `size`, in order. The order is the point —
  /// see `MailSyncEngine.cursor`.
  func slices(of size: Int) -> [[Element]] {
    guard size > 0 else { return isEmpty ? [] : [self] }
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
