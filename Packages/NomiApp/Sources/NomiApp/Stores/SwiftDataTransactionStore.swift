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

  /// Assigns the account, and - for a mail row that knows where it came from -
  /// learns from it (C4).
  ///
  /// Same signature it has always had. What changed is the effects: the user
  /// telling the app "this HDFC alert ending 4471 is my HDFC account" is the
  /// only moment the app can learn that, and before this it was thrown away
  /// after one row.
  ///
  /// Three things happen, in order:
  ///
  /// 1. **Learn.** Upsert `(senderDomain, cardFragment) -> accountID`, so the
  ///    next ingest resolves it at insert time with no prompt.
  /// 2. **Apply to siblings.** Every other email row with the same key and no
  ///    account gets it too. Assigning one of forty identical-looking alerts
  ///    and being asked forty times is the thing this exists to stop.
  /// 3. **Un-flag, narrowly.** Only rows whose flag *was* the missing account.
  ///
  /// `setAccount(_, to: nil)` un-assigns the one row and learns nothing.
  /// Bindings are never deleted here: the user is correcting a row, not
  /// necessarily retracting what they taught.
  ///
  /// The user's choice is trusted even when `Account.lastFour` disagrees with
  /// `cardFragment` - they can see both and the app cannot.
  public func setAccount(_ id: UUID, to accountID: UUID?) throws {
    guard let row = try row(id: id) else { return }
    let timestamp = now()
    row.accountID = accountID
    row.updatedAt = timestamp

    var touched: [Transaction] = [row]

    if let accountID,
      row.source == .email,
      let domain = row.senderDomain,
      let fragment = row.cardFragment
    {
      try learnBinding(domain: domain, fragment: fragment, accountID: accountID)

      for sibling in try unassignedSiblings(domain: domain, fragment: fragment, excluding: id) {
        sibling.accountID = accountID
        sibling.updatedAt = timestamp
        touched.append(sibling)
      }
    }

    // `mergedCount == 1` is the proxy for "no pipeline flag has been added
    // since insert". Every pipeline-side flag - a near merge, an account
    // conflict - arrives with a second `SourceRef`, and `merging()` bumps
    // `mergedCount` for every new ref. A row that has been merged may carry a
    // reason that is no longer the whole story, so this leaves it alone.
    for transaction in touched
    where transaction.needsReviewReason == .unidentifiedAccount
      && transaction.mergedCount == 1
      && transaction.accountID != nil
    {
      transaction.needsReview = false
    }

    try context.save()
    // No category moved, so the observer gets an empty set rather than a wrong
    // one — `IngestPipeline.ruleDeleted` makes the same call for the same
    // reason.
    coordinator.didWrite()
  }

  /// Upsert. Every duplicate for the key is updated rather than just the first,
  /// so two devices that each wrote a binding converge on the user's latest
  /// answer instead of one of them keeping a stale one (R5: no unique
  /// constraints under CloudKit).
  private func learnBinding(domain: String, fragment: String, accountID: UUID) throws {
    let existing = try context.fetch(
      FetchDescriptor<AccountBinding>(
        predicate: #Predicate<AccountBinding> {
          $0.senderDomain == domain && $0.cardFragment == fragment
        }
      ))

    guard !existing.isEmpty else {
      context.insert(
        AccountBinding(senderDomain: domain, cardFragment: fragment, accountID: accountID))
      return
    }
    for binding in existing { binding.accountID = accountID }
  }

  /// Email rows sharing the key that nobody has assigned an account to.
  /// Deliberately not rows that already have one: a row the user assigned
  /// elsewhere is not this call's to overwrite.
  private func unassignedSiblings(
    domain: String, fragment: String, excluding id: UUID
  ) throws -> [Transaction] {
    let email = IngestSource.email.rawValue
    // Bound as optionals deliberately: `Transaction.senderDomain` and
    // `cardFragment` are `String?`, and `#Predicate` will not promote a
    // non-optional operand for you the way ordinary Swift does.
    let domain: String? = domain
    let fragment: String? = fragment
    return try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.id != id
            && $0.accountID == nil
            && $0.sourceRaw == email
            && $0.senderDomain == domain
            && $0.cardFragment == fragment
        }
      ))
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
