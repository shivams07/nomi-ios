import Foundation
import NomiCore

@testable import NomiIngest

// MARK: - Fixtures

enum Fixture {
  /// Fixed calendar and time zone. CI runs UTC and Shivam does not; a test
  /// whose start-of-day depends on the runner's locale is a test that passes
  /// here and fails there.
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }

  /// `"2026-08-20"` or `"2026-08-20 18:30"`.
  static func date(_ string: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
    formatter.dateFormat = string.contains(":") ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
    guard let date = formatter.date(from: string) else {
      preconditionFailure("bad fixture date \(string)")
    }
    return date
  }

  static let commitTime = date("2026-08-26 09:00")

  static let clock: @Sendable () -> Date = { commitTime }

  static func draft(
    date: String = "2026-08-20",
    description: String = "UPI/P2M/412345678901/SWIGGY/HDFC/Order",
    amountMinor: Int = 45_900,
    direction: Direction = .debit,
    source: IngestSource = .email,
    externalID: String = "uid-1",
    accountID: UUID? = nil,
    needsReview: Bool = false,
    categoryID: UUID? = nil,
    categorySource: CategorySource = .none
  ) -> TransactionDraft {
    TransactionDraft(
      date: Fixture.date(date),
      descriptionText: description,
      amountMinor: amountMinor,
      direction: direction,
      accountID: accountID,
      source: source,
      externalID: externalID,
      capturedAt: commitTime,
      needsReview: needsReview,
      categoryID: categoryID,
      categorySource: categorySource
    )
  }

  static func rule(
    id: UUID = UUID(),
    pattern: String,
    categoryID: UUID,
    priority: Int = 0,
    isEnabled: Bool = true,
    createdAt: String = "2026-01-01"
  ) -> RuleSnapshot {
    RuleSnapshot(
      id: id,
      pattern: pattern,
      categoryID: categoryID,
      priority: priority,
      isEnabled: isEnabled,
      createdAt: Fixture.date(createdAt)
    )
  }

  /// A stored row equivalent to what `ingest` would have created for `draft`.
  static func row(
    from draft: TransactionDraft,
    id: UUID = UUID(),
    categoryID: UUID? = nil,
    categorySource: CategorySource = .none,
    appliedRuleID: UUID? = nil,
    createdAt: String = "2026-08-20 10:00"
  ) -> TransactionSnapshot {
    let derived = DraftDerivation.derive(draft, calendar: calendar)
    var row = TransactionSnapshot.creating(from: derived, now: Fixture.date(createdAt))
    row.id = id
    row.categoryID = categoryID
    row.categorySourceRaw = categorySource.rawValue
    row.appliedRuleID = appliedRuleID
    return row
  }

  static func pipeline(
    store: FakePipelineStore,
    observer: RecordingObserver? = nil
  ) async -> IngestPipeline {
    let pipeline = IngestPipeline(store: store, calendar: calendar, now: clock)
    if let observer { await pipeline.setObserver(observer) }
    return pipeline
  }
}

// MARK: - Fakes

/// In-memory `PipelineStore`. Records every `apply` so a test can assert on
/// batching, not just on final state.
actor FakePipelineStore: PipelineStore {
  private var rowsByID: [UUID: TransactionSnapshot] = [:]
  private var ruleSnapshots: [RuleSnapshot] = []
  private(set) var appliedPlans: [CommitPlan] = []

  init(rows: [TransactionSnapshot] = [], rules: [RuleSnapshot] = []) {
    for row in rows { rowsByID[row.id] = row }
    ruleSnapshots = rules
  }

  // Test accessors

  var rowCount: Int { rowsByID.count }
  var applyCount: Int { appliedPlans.count }

  var allRows: [TransactionSnapshot] {
    rowsByID.values.sorted { lhs, rhs in
      if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
      return lhs.id.uuidString < rhs.id.uuidString
    }
  }

  var onlyRow: TransactionSnapshot? {
    rowsByID.count == 1 ? rowsByID.values.first : nil
  }

  func row(_ id: UUID) -> TransactionSnapshot? { rowsByID[id] }

  func setRules(_ rules: [RuleSnapshot]) { ruleSnapshots = rules }

  // PipelineStore

  func rules() async throws -> [RuleSnapshot] {
    ruleSnapshots.filter(\.isEnabled)
  }

  func mergeCandidates(
    amountMinor: Int,
    directionRaw: String,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    rowsByID.values.filter {
      $0.amountMinor == amountMinor
        && $0.directionRaw == directionRaw
        && dateRange.contains($0.date)
    }
  }

  func rulePassCandidates() async throws -> [TransactionSnapshot] {
    rowsByID.values.filter { $0.categorySource != .manual }
  }

  func rows(appliedRuleID: UUID) async throws -> [TransactionSnapshot] {
    rowsByID.values.filter { $0.appliedRuleID == appliedRuleID }
  }

  func duplicateGroups() async throws -> [[TransactionSnapshot]] {
    var byKey: [String: [TransactionSnapshot]] = [:]
    for row in rowsByID.values where !row.dedupeKey.isEmpty {
      byKey[row.dedupeKey, default: []].append(row)
    }
    return Array(byKey.values.filter { $0.count > 1 })
  }

  func apply(_ plan: CommitPlan) async throws {
    appliedPlans.append(plan)
    for row in plan.inserts { rowsByID[row.id] = row }
    for row in plan.updates { rowsByID[row.id] = row }
    for id in plan.deletes { rowsByID.removeValue(forKey: id) }
  }
}

/// `PostCommitObserver` that records every call. `@unchecked Sendable` with an
/// explicit lock because the pipeline may call it from any executor.
final class RecordingObserver: PostCommitObserver, @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [Set<UUID>] = []

  var calls: [Set<UUID>] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  var callCount: Int { calls.count }

  func didCommit(affectedCategoryIDs: Set<UUID>) async {
    lock.lock()
    recorded.append(affectedCategoryIDs)
    lock.unlock()
  }
}
