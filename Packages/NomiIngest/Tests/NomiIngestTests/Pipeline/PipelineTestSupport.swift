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

  /// `scope` defaults here and nowhere else. `RuleSnapshot.init` gives it no
  /// default on purpose (§W2-5) so that a production construction site cannot
  /// forget it; a fixture is the one place where "no scope" is both the
  /// overwhelming case and visible in the test that asked for it.
  static func rule(
    id: UUID = UUID(),
    pattern: String,
    categoryID: UUID,
    priority: Int = 0,
    isEnabled: Bool = true,
    scope: RuleScope = .any,
    createdAt: String = "2026-01-01"
  ) -> RuleSnapshot {
    RuleSnapshot(
      id: id,
      pattern: pattern,
      categoryID: categoryID,
      priority: priority,
      isEnabled: isEnabled,
      scope: scope,
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
    let pipeline = IngestPipeline(
      store: store, calendar: calendar, transferCalendar: calendar, now: clock)
    if let observer { await pipeline.setObserver(observer) }
    return pipeline
  }
}

// MARK: - Fakes

/// In-memory `PipelineStore`. Records every `apply` so a test can assert on
/// batching, not just on final state. Transfer writes follow the real store's
/// rules: a whole pair or nothing (TR4), and only the pair and `updatedAt`.
actor FakePipelineStore: PipelineStore {
  private var rowsByID: [UUID: TransactionSnapshot] = [:]
  private var ruleSnapshots: [RuleSnapshot] = []
  private var accountsByID: [UUID: TransferAccount]
  private(set) var appliedPlans: [CommitPlan] = []
  /// One entry per `applyTransferMarks` call that landed at least one pair.
  private(set) var appliedTransferWrites: [[TransferPairWrite]] = []
  /// Makes `accountFacts()` throw, to test that a detection failure does not
  /// fail the ingest.
  private var failAccountFacts = false

  init(
    rows: [TransactionSnapshot] = [],
    rules: [RuleSnapshot] = [],
    accounts: [UUID: TransferAccount] = [:]
  ) {
    for row in rows { rowsByID[row.id] = row }
    ruleSnapshots = rules
    accountsByID = accounts
  }

  // Test accessors

  var rowCount: Int { rowsByID.count }
  var applyCount: Int { appliedPlans.count }

  func setFailAccountFacts(_ fail: Bool) { failAccountFacts = fail }

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

  func accountFacts() async throws -> [UUID: TransferAccount] {
    if failAccountFacts { throw FakeStoreFailure.accountFacts }
    return accountsByID
  }

  func transferCandidates(
    amountMinor: Int,
    dateRange: ClosedRange<Date>
  ) async throws -> [TransactionSnapshot] {
    rowsByID.values.filter {
      $0.amountMinor == amountMinor && dateRange.contains($0.date)
    }.map { row in
      // As the real store does: the read pair is the pair the row has now.
      var copy = row
      copy.transferPairAtRead = row.transferPair
      return copy
    }
  }

  /// The same decision the real store takes, on the fake's rows: `accepted`
  /// against the current state, then the pair and `updatedAt` on both legs.
  func applyTransferMarks(
    _ writes: [TransferPairWrite],
    updatedAt: Date
  ) async throws -> [TransferPairWrite] {
    var now: [UUID: TransferLegState] = [:]
    for write in writes {
      for id in [write.first.id, write.second.id] {
        if let row = rowsByID[id] {
          now[id] = TransferLegState(id: row.id, accountID: row.accountID, pair: row.transferPair)
        }
      }
    }
    let landed = TransferPairWrite.accepted(writes, now: now)
    for write in landed {
      for id in [write.first.id, write.second.id] {
        rowsByID[id]?.transferGroupID = write.pair.groupID
        rowsByID[id]?.transferSourceRaw = write.pair.sourceRaw
        rowsByID[id]?.updatedAt = updatedAt
      }
    }
    if !landed.isEmpty { appliedTransferWrites.append(landed) }
    return landed
  }
}

enum FakeStoreFailure: Error {
  case accountFacts
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
