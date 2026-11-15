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
  /// DEC-05's device calendar, for the transfer window and its read (TR1).
  private let transferCalendar: Calendar
  private let now: () -> Date
  /// The one save `setAccount` makes. A seam so a test can make it fail and
  /// prove the rollback; production passes the real `save()`.
  private let saveAccountWrite: (ModelContext) throws -> Void
  /// The one save `addTransfer` makes (I-11). A seam for the same reason: a test makes it fail
  /// and proves neither leg is left behind. Production passes the real `save()`.
  private let saveTransferWrite: (ModelContext) throws -> Void
  /// The one save `delete` makes when the row is a transfer leg (B9). A seam for the same
  /// reason: a test makes it fail and proves neither the delete nor the unpairing persists.
  /// Production passes the real `save()`.
  private let saveDeleteUnpairWrite: (ModelContext) throws -> Void

  public init(
    context: ModelContext,
    coordinator: WriteCoordinator,
    calendar: Calendar = NomiCalendar.india,
    transferCalendar: Calendar = .current,
    now: @escaping () -> Date = { Date() },
    saveAccountWrite: @escaping (ModelContext) throws -> Void = { try $0.save() },
    saveTransferWrite: @escaping (ModelContext) throws -> Void = { try $0.save() },
    saveDeleteUnpairWrite: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) {
    self.context = context
    self.coordinator = coordinator
    self.calendar = calendar
    self.transferCalendar = transferCalendar
    self.now = now
    self.saveAccountWrite = saveAccountWrite
    self.saveTransferWrite = saveTransferWrite
    self.saveDeleteUnpairWrite = saveDeleteUnpairWrite
  }

  public func add(_ draft: ManualTransactionDraft) throws -> Transaction {
    // R8. Refused before anything is built, so a refused add writes nothing.
    guard AmountRules.isValidTransactionAmount(draft.amountMinor) else {
      throw AmountValidationError.outOfRange(amountMinor: draft.amountMinor)
    }
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
      updatedAt: timestamp,
      // A new manual row is never a transfer and has no ingest facts (DEC-05, R1).
      senderDomain: nil,
      cardFragment: nil,
      needsReviewReason: nil,
      transferGroupID: nil,
      transferSourceRaw: nil
    )

    // A category the user picked is `.manual` and `RuleEngine.apply` leaves it
    // alone; one they left blank is `.none` and a rule may claim it. Same
    // precedence the pipeline gives an imported row.
    // `precedenceOrdered` here because `RuleEngine.apply` no longer sorts for
    // its caller (U10). Not a stylistic wrap: without it a manual entry would
    // be categorised by whichever rule the fetch happened to return first,
    // which is wrong precedence with nothing to indicate it.
    if let ruled = RuleEngine.apply(
      RuleEngine.precedenceOrdered(try ruleSnapshots()), to: snapshot)
    {
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
      updatedAt: snapshot.updatedAt,
      note: Self.storedNote(draft.note)
    )

    context.insert(transaction)
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: Set([snapshot.categoryID].compactMap { $0 }))
    return transaction
  }

  /// Two legs in one save (I-11). The debit leaves `fromAccountID` and the credit lands on
  /// `toAccountID`, same amount and date. Both are manual and categoryless, and neither needs review.
  ///
  /// Neither leg is `needsReview`, and `RuleEngine` is not run: a transfer is not categorised, and
  /// a rule that claimed it would put a category on a leg that must never carry one.
  ///
  /// The group is `TransferGroupID.make(debit.id, credit.id)`, derived from the two leg ids (I-11
  /// Amendment 1, PR #202). Both ids are generated before either row is built, so the group is the same
  /// whichever order the pair is read in. It is the same derivation `setTransfer` uses for marked pairs.
  public func addTransfer(
    amountMinor: Int,
    date: Date,
    fromAccountID: UUID,
    toAccountID: UUID,
    note: String?
  ) throws -> (Transaction, Transaction) {
    // R8. Refused before anything is built, so a refused transfer writes nothing.
    guard AmountRules.isValidTransactionAmount(amountMinor) else {
      throw AmountValidationError.outOfRange(amountMinor: amountMinor)
    }
    guard fromAccountID != toAccountID else { throw TransactionStoreError.sameAccount }

    let timestamp = now()
    // Both ids first, so the group is a function of the two legs (I-11 Amendment 1).
    let debitID = UUID()
    let creditID = UUID()
    let group = TransferGroupID.make(debitID, creditID)
    let storedNote = Self.storedNote(note)
    let debit = makeTransferLeg(
      id: debitID, .debit, amountMinor: amountMinor, date: date, accountID: fromAccountID,
      group: group, note: storedNote, timestamp: timestamp)
    let credit = makeTransferLeg(
      id: creditID, .credit, amountMinor: amountMinor, date: date, accountID: toAccountID,
      group: group, note: storedNote, timestamp: timestamp)
    context.insert(debit)
    context.insert(credit)

    // One save for both legs. A failed save rolls the context back, so neither leg is left for a
    // later save to flush (the TR4 shape the other writes here use).
    do {
      try saveTransferWrite(context)
    } catch {
      context.rollback()
      throw error
    }
    coordinator.didWrite(affectedCategoryIDs: [])
    return (debit, credit)
  }

  private func makeTransferLeg(
    id: UUID,
    _ direction: Direction,
    amountMinor: Int,
    date: Date,
    accountID: UUID,
    group: UUID,
    note: String?,
    timestamp: Date
  ) -> Transaction {
    let descriptionText = "Transfer"
    let normalized = normalizeDescription(descriptionText)
    return Transaction(
      id: id,
      date: date,
      descriptionText: descriptionText,
      normalizedDescription: normalized,
      amountMinor: amountMinor,
      directionRaw: direction.rawValue,
      categoryID: nil,
      categorySourceRaw: CategorySource.none.rawValue,
      accountID: accountID,
      sourceRaw: IngestSource.manual.rawValue,
      sourceRefs: [
        SourceRef(source: .manual, externalID: UUID().uuidString, capturedAt: timestamp)
      ],
      dedupeKey: makeDedupeKey(
        date: date,
        amountMinor: amountMinor,
        directionRaw: direction.rawValue,
        normalizedDescription: normalized,
        calendar: calendar
      ),
      createdAt: timestamp,
      updatedAt: timestamp,
      note: note,
      transferGroupID: group,
      transferSourceRaw: TransferSource.manual.rawValue
    )
  }

  /// I-11. The note as stored: trimmed, and nil when nothing is left after trimming.
  private static func storedNote(_ raw: String?) -> String? {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }

  /// I-11. The account of the most recently created manual row that has one, or nil. Mail and file
  /// rows do not count: they say nothing about what the user chose on the entry sheet. `fetchLimit`
  /// 1 on a sort by `createdAt`, so this is an index read.
  public func lastUsedAccountID() -> UUID? {
    let manual = IngestSource.manual.rawValue
    var descriptor = FetchDescriptor<Transaction>(
      predicate: #Predicate<Transaction> { $0.sourceRaw == manual && $0.accountID != nil },
      sortBy: [SortDescriptor(\Transaction.createdAt, order: .reverse)]
    )
    descriptor.fetchLimit = 1
    do {
      return try context.fetch(descriptor).first?.accountID
    } catch {
      NomiLog.store.error("last used account fetch failed: \(NomiLog.describe(error), privacy: .public)")
      return nil
    }
  }

  /// I-11. Categories past rows with a similar description were filed under. The text is normalised
  /// the way the rows were, so a query finds `SWIGGY ORDER` from `swiggy 4411`. Transfer legs and
  /// uncategorised rows do not count, and a category that no longer exists is dropped, so a suggestion
  /// is never a category the picker cannot show. Most frequent first, ties by the most recent matching
  /// row's date, then by id so the order is the same on every read.
  public func suggestedCategories(forDescription text: String, limit: Int) throws -> [UUID] {
    let needle = normalizeDescription(text)
    // Fewer than two characters matches nearly every row, so it is not a hint.
    guard needle.count >= 2, limit > 0 else { return [] }

    let rows = try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.normalizedDescription.contains(needle) && $0.categoryID != nil && $0.transferGroupID == nil
        }
      ))
    let existing = Set(try context.fetch(FetchDescriptor<NomiCore.Category>()).map(\.id))

    var count: [UUID: Int] = [:]
    var newest: [UUID: Date] = [:]
    for row in rows {
      guard let category = row.categoryID, existing.contains(category) else { continue }
      count[category, default: 0] += 1
      newest[category] = max(newest[category] ?? .distantPast, row.date)
    }

    let ordered = count.keys.sorted { lhs, rhs in
      if count[lhs] != count[rhs] { return (count[lhs] ?? 0) > (count[rhs] ?? 0) }
      if newest[lhs] != newest[rhs] { return (newest[lhs] ?? .distantPast) > (newest[rhs] ?? .distantPast) }
      return lhs.uuidString < rhs.uuidString
    }
    return Array(ordered.prefix(limit))
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

    // DEC-05 detector (TR2). Assigning an account can complete a pair. Marks
    // are decided before the first write, in the same span, and land in the
    // save below. Unassigning marks nothing.
    let marked: Set<UUID>
    if accountID == nil {
      marked = Set<UUID>()
    } else {
      do {
        marked = try markTransfers(touching: touched, at: timestamp)
      } catch {
        // The account change still saves; only the pair marks are skipped.
        NomiLog.store.error("transfer marking failed: \(NomiLog.describe(error), privacy: .public)")
        marked = []
      }
    }

    // A failed save must not leave the account change or the marks dirty in
    // this context, where a later save would flush them half-applied (TR4, the
    // same rollback `SwiftDataPipelineStore.applyTransferMarks` makes). Rolled
    // back and rethrown: nothing persists and the coordinator hears nothing.
    do {
      try saveAccountWrite(context)
    } catch {
      context.rollback()
      throw error
    }
    // Only the categories of legs this call marked are reported. The rest of
    // the write moved no category.
    coordinator.didWrite(affectedCategoryIDs: marked)
  }

  /// The five steps of `IngestPipeline`'s detection, on the main context (TR2).
  /// Reads and decisions finish before the first mutation. Returns the categories
  /// of the legs it marked.
  private func markTransfers(touching rows: [Transaction], at timestamp: Date) throws -> Set<UUID> {
    let seeds = rows.filter {
      $0.currencyCode == "INR" && $0.accountID != nil
        && TransferRules.state($0.transferPair) == .unmarked
    }
    guard !seeds.isEmpty else { return [] }

    // The same two-rule width as the ingest path: six days each way.
    let window = TransferRules.windowDays
    var fetched: [UUID: Transaction] = [:]
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
      var descriptor = FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> {
          $0.amountMinor == amount && $0.date >= lower && $0.date <= upper
        }
      )
      // The account just assigned is not saved yet; the read must see it.
      descriptor.includePendingChanges = true
      for row in try context.fetch(descriptor) { fetched[row.id] = row }
    }
    // The touched rows are the same managed objects, but take them by id so the
    // in-memory state is the one decided on.
    for row in seeds { fetched[row.id] = row }
    guard fetched.count >= 2 else { return [] }

    let accounts = TransferAccount.byID(
      try context.fetch(FetchDescriptor<Account>()).map { ($0.id, TransferAccount(kind: $0.kind, lastFour: $0.lastFour)) }
    )
    let snapshots = fetched.values.map { TransactionSnapshot($0) }
    let marks = TransferDetector.detect(rows: snapshots, accounts: accounts, calendar: transferCalendar)

    // In this span the read and the current state are the same fetch, so the
    // compare-and-set reduces to the state table. The write still goes through
    // `accepted`, the same decision the store takes for the ingest path.
    let states = Dictionary(uniqueKeysWithValues: fetched.values.map {
      ($0.id, TransferLegState(id: $0.id, accountID: $0.accountID, pair: $0.transferPair))
    })
    let writes = TransferPairWrite.writes(
      from: marks, readStates: states, touching: Set(seeds.map(\.id))
    )
    let landed = TransferPairWrite.accepted(writes, now: states)

    var marked: Set<UUID> = []
    for write in landed {
      for id in [write.first.id, write.second.id] {
        guard let row = fetched[id] else { continue }
        row.transferGroupID = write.pair.groupID
        row.transferSourceRaw = write.pair.sourceRaw
        row.updatedAt = timestamp
        if let category = row.categoryID { marked.insert(category) }
      }
    }
    return marked
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

  /// Deletes one row. A transfer leg also unpairs its partner (B9): the partner loses its
  /// group and its source in the same save, so it becomes an ordinary row and counts in the
  /// period totals again. Both changes persist or neither does. A row that is not a leg
  /// deletes as it always did.
  public func delete(_ id: UUID) throws {
    guard let row = try row(id: id) else { return }
    let categoryID = row.categoryID
    guard let group = row.transferGroupID else {
      context.delete(row)
      try context.save()
      // Deleting spend can only move a budget *down*, never across a threshold,
      // so this cannot fire an alert — but the progress bar and every total on
      // the dashboard do change, and that is what the invalidation is for.
      coordinator.didWrite(affectedCategoryIDs: Set([categoryID].compactMap { $0 }))
      return
    }

    // The partners are read before the first mutation. A group with no other stored
    // member (its partner was already deleted) finds none, and only the row goes.
    let target: UUID? = group
    let rowID = row.id
    let partners = try context.fetch(
      FetchDescriptor<Transaction>(
        predicate: #Predicate<Transaction> { $0.transferGroupID == target && $0.id != rowID }
      ))
    let timestamp = now()
    for partner in partners {
      partner.transferGroupID = nil
      partner.transferSourceRaw = nil
      partner.updatedAt = timestamp
    }
    context.delete(row)
    do {
      try saveDeleteUnpairWrite(context)
    } catch {
      // Neither the delete nor the unpairing stays dirty for a later save to flush.
      context.rollback()
      throw error
    }
    // Both legs' categories moved: the deleted one lost a row, the partner gained one.
    var affected = Set([categoryID].compactMap { $0 })
    affected.formUnion(partners.compactMap(\.categoryID))
    coordinator.didWrite(affectedCategoryIDs: affected)
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
    do {
      return try context.fetch(descriptor).first?.categoryID
    } catch {
      NomiLog.store.error("last used category fetch failed: \(NomiLog.describe(error), privacy: .public)")
      return nil
    }
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
