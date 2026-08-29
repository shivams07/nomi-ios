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

/// The real `AccountStore`. Rename and archive only — accounts are created by
/// the ingest path (a mail or file import binds one), never by the user, so
/// there is no `create` on the contract and none here.
@MainActor
public final class SwiftDataAccountStore: AccountStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator

  public init(context: ModelContext, coordinator: WriteCoordinator) {
    self.context = context
    self.coordinator = coordinator
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

  private func account(id: UUID) throws -> Account? {
    var descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
