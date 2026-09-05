import Foundation
import NomiCore

/// The single write path. Every `Transaction` in this app is created, merged or
/// recategorized here and nowhere else.
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
  private let now: @Sendable () -> Date
  private var observer: (any PostCommitObserver)?
  private var isBusy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  public init(
    store: any PipelineStore,
    calendar: Calendar = NomiCalendar.india,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.store = store
    self.calendar = calendar
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
    let rules = try await store.rules()
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
    try await commit(plan)

    return IngestBatchResult(created: created, merged: merged, flagged: flagged)
  }

  // MARK: - Rule lifecycle

  /// On rule create or edit: re-apply across the whole ledger where
  /// `categorySource != .manual`. This is what makes a new rule retroactive
  /// without a re-import.
  @discardableResult
  public func reapplyRules() async throws -> RuleApplyResult {
    await acquire()
    defer { release() }
    return try await performReapplyRules()
  }

  private func performReapplyRules() async throws -> RuleApplyResult {
    let rules = try await store.rules()
    let rows = try await store.rulePassCandidates()
    let timestamp = now()

    var updates: [TransactionSnapshot] = []
    var affected: Set<UUID> = []
    var matched = 0
    var recategorized = 0

    for row in rows {
      guard row.categorySource != .manual else { continue }
      guard
        RuleEngine.firstMatch(normalizedDescription: row.normalizedDescription, in: rules) != nil
      else { continue }
      matched += 1

      guard var next = RuleEngine.apply(rules, to: row) else { continue }
      if next.categoryID != row.categoryID { recategorized += 1 }
      next.updatedAt = timestamp
      note(&affected, row.categoryID, next.categoryID)
      updates.append(next)
    }

    try await commit(CommitPlan(updates: updates, affectedCategoryIDs: affected))
    return RuleApplyResult(matched: matched, recategorized: recategorized)
  }

  /// On rule delete: no re-evaluation at all. `appliedRuleID` is nulled where
  /// it pointed at this rule; `categoryID` and `categorySource` are untouched.
  @discardableResult
  public func ruleDeleted(_ ruleID: UUID) async throws -> Int {
    await acquire()
    defer { release() }
    return try await performRuleDeleted(ruleID)
  }

  private func performRuleDeleted(_ ruleID: UUID) async throws -> Int {
    let rows = try await store.rows(appliedRuleID: ruleID)
    let timestamp = now()

    var updates: [TransactionSnapshot] = []
    for row in rows {
      guard var next = RuleEngine.clearingProvenance(of: ruleID, from: row) else { continue }
      next.updatedAt = timestamp
      updates.append(next)
    }

    // No category moved, so no budget can have moved: the affected set is
    // empty and the observer gets an empty batch rather than a wrong one.
    try await commit(CommitPlan(updates: updates))
    return updates.count
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
