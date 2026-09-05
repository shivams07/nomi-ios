import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// The real `TransactionStore`.
///
/// **This is a second write path, and that is a deviation from the design — it
/// is stated here rather than discovered later.** `IngestPipeline` is meant to
/// be the only place a `Transaction` is created. It cannot be, for `add`: the
/// protocol (U1, merged, and every `NomiUI` screen is built on it) is
/// `@MainActor`, synchronous, and returns the created `Transaction`;
/// `IngestPipeline` is an actor and its `ingest` returns counts. There is no
/// signature that reaches one from the other.
///
/// What that costs, and what is done about each:
///
/// - *Dedupe.* `normalizedDescription` and `dedupeKey` are derived with
///   `NomiCore`'s public functions — the same two calls the pipeline's
///   `DraftDerivation` makes, so the keys are byte-identical. A manual row and
///   the bank email for the same transaction therefore share a key, and U4's
///   reconcile pass (which runs at launch and on every remote change) collapses
///   them. A duplicate is possible in the window between; it is not permanent,
///   and it is the same window R5 already accepts across devices.
/// - *Rules.* Applied here through `RuleEngine`, the same public type the
///   pipeline uses, over the same `TransactionSnapshot` value. Not
///   reimplemented.
/// - *Merging.* Deliberately **not** attempted. `MergeResolution` is the
///   pipeline's, and a second merge implementation is precisely the failure
///   §2.2 names for budget arithmetic. A same-key row is left for reconcile.
@MainActor
public final class SwiftDataTransactionStore: TransactionStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let calendar: Calendar
  private let now: () -> Date

  public init(
    context: ModelContext,
    coordinator: WriteCoordinator,
    calendar: Calendar = NomiCalendar.india,
    now: @escaping () -> Date = { Date() }
  ) {
    self.context = context
    self.coordinator = coordinator
    self.calendar = calendar
    self.now = now
  }

  public func add(_ draft: ManualTransactionDraft) throws -> Transaction {
    let timestamp = now()
    let normalized = normalizeDescription(draft.descriptionText)

    var snapshot = TransactionSnapshot(
      date: draft.date,
      descriptionText: draft.descriptionText,
      normalizedDescription: normalized,
      amountMinor: draft.amountMinor,
      directionRaw: draft.direction.rawValue,
      categoryID: draft.categoryID,
      categorySourceRaw: draft.categoryID == nil
        ? CategorySource.none.rawValue
        : CategorySource.manual.rawValue,
      accountID: draft.accountID,
      sourceRaw: IngestSource.manual.rawValue,
      sourceRefs: [
        SourceRef(source: .manual, externalID: UUID().uuidString, capturedAt: timestamp)
      ],
      dedupeKey: makeDedupeKey(
        date: draft.date,
        amountMinor: draft.amountMinor,
        directionRaw: draft.direction.rawValue,
        normalizedDescription: normalized,
        calendar: calendar
      ),
      createdAt: timestamp,
      updatedAt: timestamp
    )

    // A category the user picked is `.manual` and `RuleEngine.apply` leaves it
    // alone; one they left blank is `.none` and a rule may claim it. Same
    // precedence the pipeline gives an imported row.
    if let ruled = RuleEngine.apply(try ruleSnapshots(), to: snapshot) {
      snapshot = ruled
    }

    let transaction = Transaction(
      id: snapshot.id,
      date: snapshot.date,
      descriptionText: snapshot.descriptionText,
      normalizedDescription: snapshot.normalizedDescription,
      amountMinor: snapshot.amountMinor,
      directionRaw: snapshot.directionRaw,
      categoryID: snapshot.categoryID,
      categorySourceRaw: snapshot.categorySourceRaw,
      appliedRuleID: snapshot.appliedRuleID,
      accountID: snapshot.accountID,
      sourceRaw: snapshot.sourceRaw,
      sourceRefs: snapshot.sourceRefs,
      dedupeKey: snapshot.dedupeKey,
      createdAt: snapshot.createdAt,
      updatedAt: snapshot.updatedAt
    )

    context.insert(transaction)
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: Set([snapshot.categoryID].compactMap { $0 }))
    return transaction
  }

  public func setCategory(_ id: UUID, to categoryID: UUID?) throws {
    guard let row = try row(id: id) else { return }
    let previous = row.categoryID
    row.categoryID = categoryID
    // A user's choice is final: `.manual` is what stops the retroactive rule
    // pass from overwriting it on the next rule edit.
    row.categorySourceRaw = CategorySource.manual.rawValue
    row.appliedRuleID = nil
    row.updatedAt = now()
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: Set([previous, categoryID].compactMap { $0 }))
  }

  public func setAccount(_ id: UUID, to accountID: UUID?) throws {
    guard let row = try row(id: id) else { return }
    row.accountID = accountID
    row.updatedAt = now()
    try context.save()
    // No category moved, so the observer gets an empty set rather than a wrong
    // one — `IngestPipeline.ruleDeleted` makes the same call for the same
    // reason.
    coordinator.didWrite()
  }

  public func delete(_ id: UUID) throws {
    guard let row = try row(id: id) else { return }
    let categoryID = row.categoryID
    context.delete(row)
    try context.save()
    // Deleting spend can only move a budget *down*, never across a threshold,
    // so this cannot fire an alert — but the progress bar and every total on
    // the dashboard do change, and that is what the invalidation is for.
    coordinator.didWrite(affectedCategoryIDs: Set([categoryID].compactMap { $0 }))
  }

  /// Same membership as `FakeTransactionStore`: merged rows, flagged rows, and
  /// rows with no account. Expressed as one predicate so SQLite does the
  /// filtering rather than the whole ledger arriving to be filtered in Swift.
  public func reviewQueue() throws -> [Transaction] {
    let descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> {
        $0.mergedCount > 1 || $0.needsReview || $0.accountID == nil
      },
      sortBy: [SortDescriptor(\Transaction.date, order: .reverse)]
    )
    return try context.fetch(descriptor)
  }

  public func dismissReview(_ id: UUID) throws {
    guard let row = try row(id: id) else { return }
    row.needsReview = false
    row.updatedAt = now()
    try context.save()
    coordinator.didWrite()
  }

  /// The most recently categorised row's category, rather than an in-memory
  /// field like the fake's.
  ///
  /// This is what makes the entry sheet pre-select sensibly on the *first*
  /// entry after a launch, which is the only time it matters — an in-memory
  /// last-used is always nil exactly then. Sorted on `updatedAt`, limit 1, so
  /// it is an index lookup and not a scan.
  ///
  /// A nil result is a real answer, not a miss: `setCategory(_:to: nil)` also
  /// stamps `.manual`, so the most recent deliberate choice can genuinely have
  /// been "no category", and pre-selecting the one before it would override the
  /// user's last decision with their second-to-last.
  public func lastUsedCategoryID() -> UUID? {
    let manual = CategorySource.manual.rawValue
    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.categorySourceRaw == manual },
      sortBy: [SortDescriptor(\Transaction.updatedAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.categoryID
  }

  // MARK: -

  private func row(id: UUID) throws -> Transaction? {
    var descriptor = FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }

  private func ruleSnapshots() throws -> [RuleSnapshot] {
    try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.isEnabled }))
      .map { RuleSnapshot($0) }
  }
}
