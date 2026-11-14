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
    await acquire()
    defer { release() }
    return try await performIngest(drafts)
  }

  private func performIngest(_ drafts: [TransactionDraft]) async throws -> IngestBatchResult {
    // Ordered once per pass, not once per row. `RuleEngine.firstMatch` used to
    // sort internally, so a batch of 50 drafts sorted the rule set 100 times
    // to answer the same question 100 times.
    let rules = RuleEngine.precedenceOrdered(try await store.rules())
    let timestamp = now()

    var working: [UUID: TransactionSnapshot] = [:]
    var insertedIDs: [UUID] = []
    var updatedIDs: [UUID] = []
    var affected: Set<UUID> = []
    var created = 0
    var merged = 0
    var flagged = 0

    for draft in drafts {
      let derived = DraftDerivation.derive(draft, calendar: calendar)
      let range = DedupeMatcher.candidateDateRange(for: draft.date, calendar: calendar)

      let stored = try await store.mergeCandidates(
        amountMinor: draft.amountMinor,
        directionRaw: draft.direction.rawValue,
        dateRange: range
      )

      var candidates = stored.map { working[$0.id] ?? $0 }
      let storedIDs = Set(stored.map(\.id))
      candidates.append(
        contentsOf: working.values.filter { row in
          !storedIDs.contains(row.id)
            && row.amountMinor == draft.amountMinor
            && row.directionRaw == draft.direction.rawValue
            && range.contains(row.date)
        }
      )

      if let hit = DedupeMatcher.match(derived, in: candidates, calendar: calendar) {
        merged += 1
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

        if next.needsReview && !before.needsReview { flagged += 1 }
        note(&affected, before.categoryID, next.categoryID)

        working[next.id] = next
        if !insertedIDs.contains(next.id) && !updatedIDs.contains(next.id) {
          updatedIDs.append(next.id)
        }
        continue
      }

      var row = TransactionSnapshot.creating(from: derived, now: timestamp)
      if let ruled = RuleEngine.apply(rules, to: row) { row = ruled }

      created += 1
      if row.needsReview { flagged += 1 }
      note(&affected, row.categoryID)

      working[row.id] = row
      insertedIDs.append(row.id)
    }

    let plan = CommitPlan(
      inserts: insertedIDs.compactMap { working[$0] },
      updates: updatedIDs.compactMap { working[$0] },
      affectedCategoryIDs: affected
    )
    if !plan.isEmpty {
      try await store.apply(plan)
      // Transfer marks are a second write, made only through
      // `applyTransferMarks` (TR4). Their categories join the one observer call
      // for the batch; with no marks the call is what it was before.
      let marked = await markTransfers(touching: plan.inserts + plan.updates, at: timestamp)
      await observer?.didCommit(affectedCategoryIDs: plan.affectedCategoryIDs.union(marked))
    }

    return IngestBatchResult(created: created, merged: merged, flagged: flagged)
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
    await acquire()
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
