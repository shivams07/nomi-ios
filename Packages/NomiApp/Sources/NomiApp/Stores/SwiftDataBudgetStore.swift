import Foundation
import NomiCore
import SwiftData

/// The real `BudgetStore`.
///
/// `setBudget` fires the post-commit hook itself, and that is the whole point
/// of this type existing rather than being three lines inline (design v9.5, the
/// U8 block):
///
/// > A budget LOWERED under existing spend crosses its threshold with no
/// > pipeline commit, so U4's hook never fires and U10's observer never runs.
///
/// It goes through `WriteCoordinator.didWrite`, which calls the observer's
/// `didCommit` — **not** `BudgetAlertEvaluator.evaluate` directly.
/// `BudgetAlertObserver.didCommit` re-reads the context, filters to the
/// affected categories, writes the log rows *before* scheduling, and is
/// idempotent through `firedKeys`. Calling `evaluate` from here would mean
/// re-implementing that ordering, and the record-then-schedule guarantee is the
/// one thing in this feature that must not be got wrong twice.
@MainActor
public final class SwiftDataBudgetStore: BudgetStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator

  public init(context: ModelContext, coordinator: WriteCoordinator) {
    self.context = context
    self.coordinator = coordinator
  }

  /// Zero means remove, matching `FakeBudgetStore` — which is the shape
  /// `BudgetEditorSheet` was written against, so a store that stored a zero
  /// budget instead would render a bar at infinity percent.
  public func setBudget(categoryID: UUID, amountMinor: Int) throws {
    guard amountMinor > 0 else {
      try removeBudget(categoryID: categoryID)
      return
    }

    if let existing = try budget(categoryID: categoryID) {
      existing.amountMinor = amountMinor
      existing.isEnabled = true
    } else {
      context.insert(Budget(categoryID: categoryID, amountMinor: amountMinor))
    }
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: [categoryID])
  }

  /// Removing a budget cannot cross a threshold — there is no threshold left —
  /// so the observer is given an empty set and only the cache is dropped.
  ///
  /// The `BudgetAlertLog` rows are deliberately left in place. They are the
  /// record of what already fired this month; deleting them would let a budget
  /// removed and re-added on the same day fire a second notification for a
  /// crossing the user was already told about.
  public func removeBudget(categoryID: UUID) throws {
    guard let existing = try budget(categoryID: categoryID) else { return }
    context.delete(existing)
    try context.save()
    coordinator.didWrite()
  }

  public func budgets() throws -> [Budget] {
    try context.fetch(
      FetchDescriptor<Budget>(sortBy: [SortDescriptor(\Budget.createdAt, order: .forward)])
    )
  }

  // MARK: -

  /// One budget per category is the model's implicit rule and nothing enforces
  /// it — CloudKit forbids unique constraints (R5), so a second device can
  /// create a second row for the same category. Taking the oldest keeps the
  /// choice stable across devices instead of depending on fetch order; the
  /// duplicate is harmless because `budgetProgress` groups by `categoryID`.
  private func budget(categoryID: UUID) throws -> Budget? {
    var descriptor = FetchDescriptor<Budget>(
      predicate: #Predicate<Budget> { $0.categoryID == categoryID },
      sortBy: [SortDescriptor(\Budget.createdAt, order: .forward)]
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}

/// The real `AccountStore`.
@MainActor
public final class SwiftDataAccountStore: AccountStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator

  public init(context: ModelContext, coordinator: WriteCoordinator) {
    self.context = context
    self.coordinator = coordinator
  }

  /// The user's own account, created from the Accounts screen.
  ///
  /// It ends with `coordinator.didWrite()` and that line is the whole feature.
  /// `InsightsStore.accountSummaries` is cache-gated
  /// (`SwiftDataInsightsStore.swift:79`), and the Accounts screen and the
  /// dashboard both read accounts through it rather than through a `@Query`.
  /// Save without the invalidation and the row is in the store, correct and
  /// fetchable, and invisible on every screen until some unrelated write drops
  /// the cache — which reads as "creating an account does nothing" and then
  /// as "it worked eventually", the two worst shapes a bug can take.
  ///
  /// No category is affected, so the set stays empty: the budget observer has
  /// nothing to evaluate here, and passing an id would schedule a pass over a
  /// category this write did not touch.
  ///
  /// **Validated here** (U15). It used to validate nothing and lean on
  /// `AccountCreateFormGate`, which was one SwiftUI form's `Save` button - fine
  /// while that was the only caller, and a silent data-integrity hole the
  /// moment it was not. A malformed `lastFour` in particular has no visible
  /// symptom: it is the `cardFragment` half of the `AccountBinding` key, so
  /// the only sign is that mail auto-resolution quietly never matches.
  ///
  /// The name is stored trimmed. The gate already trims before deciding, so a
  /// name that passes the gate and a name this stores were already the same
  /// string in every case the form produces.
  @discardableResult
  public func create(
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String
  ) throws -> Account {
    let trimmedName = try Self.validated(
      displayName: displayName, lastFour: lastFour, kindRaw: kindRaw)

    let account = Account(
      displayName: trimmedName,
      institution: institution,
      lastFour: lastFour,
      kindRaw: kindRaw
    )
    context.insert(account)
    try context.save()
    coordinator.didWrite()
    return account
  }

  /// The rules `create` and `update` both enforce, in one place, returning the
  /// trimmed name so neither can validate one string and store another.
  ///
  /// Static and free of the context on purpose: it decides nothing about
  /// storage, and a caller that forgets to call it is a caller that does not
  /// have a name to store.
  private static func validated(
    displayName: String,
    lastFour: String,
    kindRaw: String
  ) throws -> String {
    let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { throw AccountStoreError.blankName }
    guard lastFour.isEmpty
      || (lastFour.count == 4 && lastFour.allSatisfy { $0.isASCII && $0.isNumber })
    else { throw AccountStoreError.malformedLastFour }
    guard AccountKind(rawValue: kindRaw) != nil else {
      throw AccountStoreError.unknownKind(kindRaw)
    }
    return trimmedName
  }

  public func rename(_ id: UUID, to displayName: String) throws {
    guard let account = try account(id: id) else { return }
    account.displayName = displayName
    try context.save()
    coordinator.didWrite()
  }

  /// Archiving hides an account from the dashboard and the active list. It
  /// deletes nothing — not the account, and not its transactions, which stay in
  /// every total. An archived card is one the user stopped using, not one whose
  /// history they are disowning.
  public func setArchived(_ id: UUID, _ archived: Bool) throws {
    guard let account = try account(id: id) else { return }
    account.isArchived = archived
    try context.save()
    coordinator.didWrite()
  }

  /// Validation runs **before** the lookup, so a malformed edit of an account
  /// that no longer exists throws rather than silently succeeding. An unknown
  /// id is still a no-op, the shape `rename` and `setArchived` already have.
  public func update(
    _ id: UUID,
    displayName: String,
    institution: String,
    lastFour: String,
    kindRaw: String,
    openingBalanceMinor: Int?
  ) throws {
    let trimmedName = try Self.validated(
      displayName: displayName, lastFour: lastFour, kindRaw: kindRaw)

    guard let account = try account(id: id) else { return }
    account.displayName = trimmedName
    account.institution = institution
    account.lastFour = lastFour
    account.kindRaw = kindRaw
    account.openingBalanceMinor = openingBalanceMinor
    try context.save()
    coordinator.didWrite()
  }

  /// Orphan the transactions, delete the bindings, delete the account.
  ///
  /// The order matters in one direction only: the rows must be re-pointed
  /// before the `Account` goes, because after the delete there is no id to
  /// fetch them by. Nothing here is a cascade — `Transaction.accountID` is a
  /// bare `UUID?`, not a SwiftData relationship, so a deleted `Account` leaves
  /// rows pointing at an id that resolves to nothing, which renders as an
  /// account name that is simply blank. That is the bug this method exists to
  /// not have.
  ///
  /// The whole thing is one `save`. A crash between the three fetches would
  /// otherwise leave bindings resolving mail onto a deleted account.
  public func delete(_ id: UUID) throws {
    guard let account = try account(id: id) else { return }

    // Typed `UUID?` rather than leaning on `UUID` promoting inside the macro:
    // `Transaction.accountID` is optional and the comparison is written at the
    // same optionality as the column.
    let target: UUID? = id
    let owned = try context.fetch(
      FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.accountID == target }))
    for row in owned { row.accountID = nil }

    let bindings = try context.fetch(
      FetchDescriptor<AccountBinding>(
        predicate: #Predicate<AccountBinding> { $0.accountID == id }))
    for binding in bindings { context.delete(binding) }

    context.delete(account)
    try context.save()
    coordinator.didWrite()
  }

  private func account(id: UUID) throws -> Account? {
    var descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
