import Foundation
import NomiCore

/// The single ingest write path. Every `Transaction` an ingester produces is
/// created or merged here and nowhere else. Rule create, edit and delete are
/// not: `SwiftDataRuleStore` drives that pass on the main context, through the
/// same `RuleEngine` calls.
///
/// Serialization is the point, and `actor` alone does not provide it: Swift
/// actors are *reentrant*, so a second `ingest` can start while the first is
/// suspended on a store `await` — both read the merge candidates, both find
/// nothing, both insert. That is a check-then-act race and it is exactly what
/// the design forbids between mail sync and file import.
///
/// So every public entry point takes an in-actor mutex and holds it across the
/// whole read-decide-write span. `SerializedWriteTests` is the regression: it
/// failed on the first CI run against a plain reentrant actor.
///
/// The design says "one ModelActor". It is split in two here — this actor holds
/// the decisions, `SwiftDataPipelineStore` (a `@ModelActor`) holds the
/// `ModelContext` — because a `@ModelActor` cannot be instantiated under
/// `swift test` in this CI, and this project's only verification mechanism is
/// CI. Serialization is unaffected: every write still funnels through this one
/// actor. See `PipelineStore`.
public actor IngestPipeline {
  private let store: any PipelineStore
  private let calendar: Calendar
  /// DEC-05's device calendar. The detector and its read window use this and
  /// nothing else; `calendar` stays `NomiCalendar.india` for dedupe.
  private let transferCalendar: Calendar
  private let now: @Sendable () -> Date
  private var observer: (any PostCommitObserver)?
  private var isBusy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  /// Bumped by `runExclusiveForErase`. A batch records it on entry; if it has
  /// moved by the time the batch gets the lock, the batch was fetched before an
  /// erase and must not write after it.
  private var epoch = 0

  public init(
    store: any PipelineStore,
    calendar: Calendar = NomiCalendar.india,
    transferCalendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.calendar = calendar
    self.transferCalendar = transferCalendar
    self.now = now
  }

  /// U8 wires U10's budget observer here. U4 does not know what it is for and
  /// must not: the hook takes category ids, not budgets.
  public func setObserver(_ observer: (any PostCommitObserver)?) {
    self.observer = observer
  }

  // MARK: - Ingest

  /// `TransactionDraft` -> dedupe (both tiers) -> rules -> persist.
  ///
  /// One commit batch, whatever the draft count. Drafts are processed in the
  /// order given and each one sees the effect of the ones before it, so two
  /// drafts for the same transaction inside a single batch collapse into one
  /// row exactly as they would across two batches.
  @discardableResult
  public func ingest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    guard !drafts.isEmpty else { return .empty }
    let entered = epoch
    await acquire()
    guard epoch == entered else {
      release()
      throw CancellationError()
    }
    defer { release() }
    return try await performIngest(drafts)
  }

  // MARK: - Simulate (I-12, Amendment 1)

  /// The ingest loop run without writing. The dry run asks this, so its counts
  /// are commit's counts by construction: same drafts, same rules, same decisions.
  ///
  /// The lock is taken and released once per chunk of `MailSyncEngine.fetchBatchSize`,
  /// as commit's batches take it, so a long file does not hold it for its length.
  /// Working rows carry across chunks, so a repeat in a later chunk is seen as a
  /// repeat of a row created in an earlier one. Nothing is written: no `apply`, no
  /// `applyTransferMarks`, no observer call.
  ///
  /// The epoch is captured once, on entry. A chunk that finds it moved (an erase
  /// has run since the drafts were fetched) throws `CancellationError`, as `ingest`
  /// does.
  public func simulate(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    guard !drafts.isEmpty else { return .empty }
    let entered = epoch
    let timestamp = now()
    var state = BatchState()
    var offset = 0
    for chunk in drafts.slices(of: MailSyncEngine.fetchBatchSize) {
      try await simulateChunk(chunk, offset: offset, entered: entered, timestamp: timestamp, into: &state)
      offset += chunk.count
      // A writer queued behind this chunk (an erase, a mail sync) is granted the
      // lock here, before the next chunk's epoch check. Without the yield this
      // task could retake the lock straight after its own release.
      await Task.yield()
    }
    return state.result
  }

  private func simulateChunk(
    _ chunk: [TransactionDraft],
    offset: Int,
    entered: Int,
    timestamp: Date,
    into state: inout BatchState
  ) async throws {
    await acquire()
    guard epoch == entered else {
      release()
      throw CancellationError()
    }
    defer { release() }
    let rules = RuleEngine.precedenceOrdered(try await store.rules())
    try await process(chunk, offset: offset, rules: rules, timestamp: timestamp, into: &state)
  }

  // MARK: - Ingest loop, shared by ingest and simulate

  /// What one pass of the ingest loop has decided so far. `ingest` makes one pass
  /// over its batch; `simulate` makes one pass over every chunk, in order.
  private struct BatchState {
    var working: [UUID: TransactionSnapshot] = [:]
    var insertedIDs: [UUID] = []
    var updatedIDs: [UUID] = []
    var affected: Set<UUID> = []
    var created = 0
    var merged = 0
    var flagged = 0
    var mergeTargetIDs: [UUID] = []
    var createdDraftIndexes: [Int] = []

    var result: IngestBatchResult {
      IngestBatchResult(
        created: created,
        merged: merged,
        flagged: flagged,
        createdIDs: insertedIDs,
        mergeTargetIDs: mergeTargetIDs,
        createdDraftIndexes: createdDraftIndexes
      )
    }
  }

  private func performIngest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    // Ordered once per pass, not once per row. `RuleEngine.firstMatch` used to
    // sort internally, so a batch of 50 drafts sorted the rule set 100 times
    // to answer the same question 100 times.
    let rules = RuleEngine.precedenceOrdered(try await store.rules())
    let timestamp = now()

    var state = BatchState()
    try await process(drafts, offset: 0, rules: rules, timestamp: timestamp, into: &state)

    let plan = CommitPlan(
      inserts: state.insertedIDs.compactMap { state.working[$0] },
      updates: state.updatedIDs.compactMap { state.working[$0] },
      affectedCategoryIDs: state.affected
    )
    if !plan.isEmpty {
      try await store.apply(plan)
      // Transfer marks are a second write, made only through
      // `applyTransferMarks` (TR4). Their categories join the one observer call
      // for the batch; with no marks the call is what it was before.
      let marked = await markTransfers(touching: plan.inserts + plan.updates, at: timestamp)
      await observer?.didCommit(affectedCategoryIDs: plan.affectedCategoryIDs.union(marked))
    }

    return state.result
  }

  /// The loop itself: each draft is merged into a candidate or created, and the
  /// decision is recorded in `state`. Draft `offset + i` is `drafts[i]` in the
  /// array the caller was given, so `createdDraftIndexes` names drafts in that
  /// array's order whether it is one batch or a chunk of a larger pass.
  private func process(
    _ drafts: [TransactionDraft],
    offset: Int,
    rules: [RuleSnapshot],
    timestamp: Date,
    into state: inout BatchState
  ) async throws {
    for (position, draft) in drafts.enumerated() {
      let derived = DraftDerivation.derive(draft, calendar: calendar)
      let range = DedupeMatcher.candidateDateRange(for: draft.date, calendar: calendar)

      let stored = try await store.mergeCandidates(
        amountMinor: draft.amountMinor,
        directionRaw: draft.direction.rawValue,
        dateRange: range
      )

      var candidates = stored.map { state.working[$0.id] ?? $0 }
      let storedIDs = Set(stored.map(\.id))
      candidates.append(
        contentsOf: state.working.values.filter { row in
          !storedIDs.contains(row.id)
            && row.amountMinor == draft.amountMinor
            && row.directionRaw == draft.direction.rawValue
            && range.contains(row.date)
        }
      )

      if let hit = DedupeMatcher.match(derived, in: candidates, calendar: calendar) {
        state.merged += 1
        // The row this draft folds into, counted whether or not anything changes.
        state.mergeTargetIDs.append(hit.row.id)
        let before = hit.row

        guard
          var next = MergeResolution.merging(
            derived, into: before, tier: hit.tier, now: timestamp
          )
        else {
          continue  // this contributor is already on the row; a true no-op
        }

        if let ruled = RuleEngine.apply(rules, to: next) {
          next = ruled
          next.updatedAt = timestamp
        }

        if next.needsReview && !before.needsReview { state.flagged += 1 }
        note(&state.affected, before.categoryID, next.categoryID)

        state.working[next.id] = next
        if !state.insertedIDs.contains(next.id) && !state.updatedIDs.contains(next.id) {
          state.updatedIDs.append(next.id)
        }
        continue
      }

      var row = TransactionSnapshot.creating(from: derived, now: timestamp)
      if let ruled = RuleEngine.apply(rules, to: row) { row = ruled }

      state.created += 1
      if row.needsReview { state.flagged += 1 }
      note(&state.affected, row.categoryID)

      state.working[row.id] = row
      state.insertedIDs.append(row.id)
      state.createdDraftIndexes.append(offset + position)
    }
  }

  // MARK: - Transfer detection (DEC-05, TR1 to TR5)

  /// Marks the pairs this batch touched. Never throws: the ingest is already
  /// committed, so a failure here leaves the rows counted as spend, which is
  /// the visible failure DEC-05 prefers. Returns the categories of the legs it
  /// wrote.
  private func markTransfers(touching rows: [TransactionSnapshot], at timestamp: Date) async -> Set<UUID> {
    do {
      return try await performMarkTransfers(touching: rows, at: timestamp)
    } catch {
      NomiLog.ingest.error("transfer marking failed: \(NomiLog.describe(error), privacy: .public)")
      return []
    }
  }

  private func performMarkTransfers(touching rows: [TransactionSnapshot], at timestamp: Date) async throws -> Set<UUID> {
    let seeds = rows.filter {
      $0.currencyCode == "INR" && $0.accountID != nil
        && TransferRules.state($0.transferPair) == .unmarked
    }
    guard !seeds.isEmpty else { return [] }

    // One read per amount, over the seeds' dates widened by the window. Two
    // rules set the width: a partner lies within `windowDays` of its seed, and
    // the partner's own competitors lie within `windowDays` of the partner, so
    // six days each way is the most a decision can need. Reading more is safe:
    // eligibility is exact, and an extra row can only add a true competitor.
    let window = TransferRules.windowDays
    var candidates: [TransactionSnapshot] = []
    for (amount, group) in Dictionary(grouping: seeds, by: \.amountMinor).sorted(by: { $0.key < $1.key }) {
      guard
        let minDate = group.map(\.date).min(),
        let maxDate = group.map(\.date).max(),
        let lower = transferCalendar.date(
          byAdding: .day, value: -(2 * window + 1),
          to: transferCalendar.startOfDay(for: minDate)),
        let upper = transferCalendar.date(
          byAdding: .day, value: 2 * window + 2,
          to: transferCalendar.startOfDay(for: maxDate))
      else { continue }
      candidates.append(contentsOf: try await store.transferCandidates(amountMinor: amount, dateRange: lower...upper))
    }

    var byID: [UUID: TransactionSnapshot] = [:]
    for row in candidates { byID[row.id] = row }
    guard byID.count >= 2 else { return [] }
    let accounts = try await store.accountFacts()

    let marks = TransferDetector.detect(
      rows: Array(byID.values), accounts: accounts, calendar: transferCalendar
    )
    let readStates = Dictionary(uniqueKeysWithValues: byID.values.map {
      ($0.id, TransferLegState(id: $0.id, accountID: $0.accountID, pair: $0.transferPairAtRead))
    })
    let writes = TransferPairWrite.writes(
      from: marks, readStates: readStates, touching: Set(seeds.map(\.id))
    )
    guard !writes.isEmpty else { return [] }

    let landed = try await store.applyTransferMarks(writes, updatedAt: timestamp)
    return Set(landed.flatMap { [$0.first.id, $0.second.id] }.compactMap { byID[$0]?.categoryID })
  }

  // MARK: - R5 reconcile

  /// CloudKit forbids unique constraints, so two devices can each create a
  /// locally-unique row for the same transaction and sync merges them into two
  /// rows. Run on launch and on every remote-change notification. Mandatory,
  /// not defensive (R5).
  @discardableResult
  public func reconcile() async throws -> ReconcileResult {
    let entered = epoch
    await acquire()
    guard epoch == entered else {
      release()
      throw CancellationError()
    }
    defer { release() }
    return try await performReconcile()
  }

  private func performReconcile() async throws -> ReconcileResult {
    let groups = try await store.duplicateGroups()
    guard !groups.isEmpty else { return .empty }

    let timestamp = now()
    var updates: [TransactionSnapshot] = []
    var deletes: [UUID] = []
    var affected: Set<UUID> = []
    var collapsed = 0

    for group in groups {
      guard let outcome = MergeResolution.collapsing(group, now: timestamp) else { continue }
      collapsed += 1
      updates.append(outcome.survivor)
      deletes.append(contentsOf: outcome.removed)
      for row in group { note(&affected, row.categoryID) }
      note(&affected, outcome.survivor.categoryID)
    }

    try await commit(
      CommitPlan(updates: updates, deletes: deletes, affectedCategoryIDs: affected)
    )
    return ReconcileResult(groupsCollapsed: collapsed, rowsRemoved: deletes.count)
  }

  // MARK: - Commit

  /// The one place `apply` and the observer are called. Once per batch, never
  /// once per row. An empty plan is not a commit, so it does not notify.
  private func commit(_ plan: CommitPlan) async throws {
    guard !plan.isEmpty else { return }
    try await store.apply(plan)
    await observer?.didCommit(affectedCategoryIDs: plan.affectedCategoryIDs)
  }

  // MARK: - Erase (B5a)

  /// Erase's turn at the pipeline. Takes the same lock as every batch, bumps the
  /// epoch so that a batch already queued behind it throws `CancellationError`
  /// instead of writing, and runs `body` before releasing.
  ///
  /// `body` must not call back into this pipeline. The lock is not re-entrant,
  /// and the call would wait on itself.
  public func runExclusiveForErase<T: Sendable>(
    _ body: @Sendable () async throws -> T
  ) async rethrows -> T {
    await acquire()
    epoch += 1
    defer { release() }
    return try await body()
  }

  // MARK: - Exclusive access
  //
  // An in-actor mutex. Actor isolation makes `isBusy` and `waiters` safe to
  // touch; what it does not do is keep one batch's read and write adjacent,
  // and that is what this restores.

  private func acquire() async {
    while isBusy {
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
    }
    isBusy = true
  }

  private func release() {
    isBusy = false
    guard !waiters.isEmpty else { return }
    waiters.removeFirst().resume()
  }

  private func note(_ set: inout Set<UUID>, _ ids: UUID?...) {
    for id in ids {
      if let id { set.insert(id) }
    }
  }
}
