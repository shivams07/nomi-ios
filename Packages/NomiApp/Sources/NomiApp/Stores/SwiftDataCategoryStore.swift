import Foundation
import NomiCore
import SwiftData

public enum AppStoreError: Error, Sendable, Equatable {
  /// A seeded category. `CategoriesScreen` checks `isSystem` before calling and
  /// shows its own copy, so this is the store-side backstop the screen's own
  /// doc comment says exists — not the user-facing path.
  case systemCategoryCannotBeDeleted
}

/// The real `CategoryStore`.
///
/// The interesting part is `delete`, which is not a one-row delete. SwiftData
/// has no foreign keys here — `Transaction.categoryID`, `Rule.categoryID` and
/// `Budget.categoryID` are bare `UUID`s — so deleting the row leaves every
/// reference dangling, and a dangling id is worse than a nil one: the category
/// breakdown resolves an unknown id to the name "Uncategorized", so two deleted
/// categories produce two separate slices both labelled "Uncategorized" and the
/// chart legend reads as a bug. Nil is a value the whole app already handles.
@MainActor
public final class SwiftDataCategoryStore: CategoryStore {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let now: () -> Date

  public init(context: ModelContext, coordinator: WriteCoordinator, now: @escaping () -> Date = { Date() }) {
    self.context = context
    self.coordinator = coordinator
    self.now = now
  }

  /// Creates a user category under the same rules `update` applies. Every rule
  /// is checked against every existing name before anything is inserted, so a
  /// refused create writes nothing: no row, no save, no cache invalidation.
  ///
  /// The stored name is the normalised one, so `"  Home \n Office "` is kept as
  /// `"Home Office"`. A case-variant or whitespace-padded duplicate is refused,
  /// not stored beside its twin. A slot outside `0..<7` is refused, not clamped.
  ///
  /// Nothing here touches a transaction. A new category has no rows, so no
  /// amount or category assignment moves.
  public func create(name: String, symbolName: String, paletteSlot: Int) throws -> NomiCore.Category {
    let existing = try context.fetch(FetchDescriptor<NomiCore.Category>())
    let stored = try CategoryEditRules.validate(
      name: name,
      symbolName: symbolName,
      paletteSlot: paletteSlot,
      otherNames: existing.map(\.name)
    )
    let category = NomiCore.Category(
      name: stored,
      symbolName: symbolName,
      paletteSlot: paletteSlot,
      isSystem: false,
      sortIndex: (existing.map(\.sortIndex).max() ?? -1) + 1
    )
    context.insert(category)
    try context.save()
    coordinator.didWrite()
    return category
  }

  public func rename(_ id: UUID, to name: String) throws {
    guard let category = try category(id: id) else { return }
    category.name = name
    try context.save()
    coordinator.didWrite()
  }

  /// Name, icon and colour in one save. Every rule is checked before the row is
  /// touched, so a refused edit leaves the row as it was. System categories are
  /// editable here; only `delete` refuses them. The seed matches by id, so a
  /// renamed system category is still that category to the reconciler.
  ///
  /// Nothing moves between categories, so the observer is not called, as with
  /// `rename`. Transactions are not written at all.
  public func update(_ id: UUID, name: String, symbolName: String, paletteSlot: Int) throws {
    guard let category = try category(id: id) else { throw CategoryUpdateError.notFound(id) }

    let others = try context.fetch(FetchDescriptor<NomiCore.Category>())
      .filter { $0.id != id }
      .map(\.name)
    let stored = try CategoryEditRules.validate(
      name: name,
      symbolName: symbolName,
      paletteSlot: paletteSlot,
      otherNames: others
    )

    category.name = stored
    category.symbolName = symbolName
    category.paletteSlot = paletteSlot
    try context.save()
    coordinator.didWrite()
  }

  public func delete(_ id: UUID) throws {
    guard let category = try category(id: id) else { return }
    guard !category.isSystem else { throw AppStoreError.systemCategoryCannotBeDeleted }

    let target: UUID? = id
    let timestamp = now()

    // Transactions fall back to uncategorized, and lose their rule provenance
    // with it: `appliedRuleID` pointing at a rule for a category that no longer
    // exists is a claim the app cannot honour.
    for row in try context.fetch(
      FetchDescriptor<Transaction>(predicate: #Predicate<Transaction> { $0.categoryID == target })
    ) {
      row.categoryID = nil
      row.categorySourceRaw = CategorySource.none.rawValue
      row.appliedRuleID = nil
      row.updatedAt = timestamp
    }

    // Rules and budgets for a category that is gone are deleted, not orphaned.
    // A rule pointing at a dead category would silently re-categorize rows into
    // nothing on the next pass; a budget would render a progress bar with no
    // name and could still fire an alert.
    for rule in try context.fetch(
      FetchDescriptor<Rule>(predicate: #Predicate<Rule> { $0.categoryID == id })
    ) {
      context.delete(rule)
    }
    for budget in try context.fetch(
      FetchDescriptor<Budget>(predicate: #Predicate<Budget> { $0.categoryID == id })
    ) {
      context.delete(budget)
    }

    context.delete(category)
    try context.save()
    coordinator.didWrite(affectedCategoryIDs: [id])
  }

  // MARK: -

  private func category(id: UUID) throws -> NomiCore.Category? {
    var descriptor = FetchDescriptor<NomiCore.Category>(
      predicate: #Predicate<NomiCore.Category> { $0.id == id }
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
  }
}
