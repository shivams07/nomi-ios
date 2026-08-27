import Foundation
import NomiCore

/// Fetch, pre-filter, extract, hand to the pipeline, count.
///
/// It never writes a `Transaction` — U4's pipeline is the single write path, and
/// this engine's only output besides drafts is the `SyncSummary`.
public actor MailSyncEngine {
  private let fetcher: any MailFetching
  private let extractor: MailTransactionExtractor
  private let pipeline: any DraftIngesting
  private let mailboxName: String
  private let now: @Sendable () -> Date

  /// Advanced only after a batch has been handed to the pipeline. If ingestion
  /// throws, the cursor stays where it was and the same UIDs are re-fetched next
  /// sync — which is safe because re-ingesting an identical `SourceRef` is a
  /// total no-op in U4, not a duplicate row.
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
  @discardableResult
  public func syncNow() async throws -> SyncSummary {
    let state = try await fetcher.selectMailbox(mailboxName)

    let uids: [UInt32]
    if let cursor, cursor.uidValidity == state.uidValidity, cursor.mailbox == mailboxName {
      uids = try await fetcher.uids(after: cursor.lastSeenUID, in: mailboxName)
    } else {
      uids = try await fetcher.uids(since: Date(timeIntervalSince1970: 0), in: mailboxName)
    }

    return try await process(uids: uids, state: state)
  }

  /// The first run: six months back (§1.3, R11). This is also the run that
  /// produces `unmatchedSenders` — the measurement that tells us which banks the
  /// user actually has, computed on their own device (§2.5.1).
  @discardableResult
  public func backfill(months: Int) async throws -> SyncSummary {
    let state = try await fetcher.selectMailbox(mailboxName)

    var components = DateComponents()
    components.month = -months
    let since = Calendar(identifier: .gregorian).date(byAdding: components, to: now())
      ?? Date(timeIntervalSince1970: 0)

    let uids = try await fetcher.uids(since: since, in: mailboxName)
    return try await process(uids: uids, state: state)
  }

  // MARK: -

  private func process(uids: [UInt32], state: MailboxState) async throws -> SyncSummary {
    guard !uids.isEmpty else {
      cursor = MailSyncCursor(
        mailbox: mailboxName, uidValidity: state.uidValidity,
        lastSeenUID: cursor?.lastSeenUID ?? 0)
      return Self.emptySummary
    }

    let messages = try await fetcher.fetch(uids: uids, in: mailboxName)
    let outcome = classify(messages)

    let batch = outcome.drafts.isEmpty
      ? IngestBatchResult.empty
      : try await pipeline.ingest(outcome.drafts)

    cursor = MailSyncCursor(
      mailbox: mailboxName,
      uidValidity: state.uidValidity,
      lastSeenUID: max(uids.max() ?? 0, cursor?.lastSeenUID ?? 0)
    )

    return SyncSummary(
      scanned: messages.count,
      created: batch.created,
      merged: batch.merged,
      flagged: batch.flagged,
      packMatched: outcome.packMatched,
      heuristicMatched: outcome.heuristicMatched,
      unmatchedSenders: outcome.tally.top()
    )
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
