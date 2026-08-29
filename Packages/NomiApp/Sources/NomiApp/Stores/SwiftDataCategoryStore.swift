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

  public func create(name: String, symbolName: String, paletteSlot: Int) throws -> NomiCore.Category {
    let existing = try context.fetch(FetchDescriptor<NomiCore.Category>())
    let category = NomiCore.Category(
      name: name,
      symbolName: symbolName,
      // The editor offers 0...6 (`PaletteSlotOptions`), but the store is not
      // the editor's downstream — clamping here means a slot can never be
      // stored that `paletteSlot(_:)` would resolve to the grey Other hue by
      // accident rather than by the deliberate eighth-category rule.
      paletteSlot: min(max(paletteSlot, 0), CategorySeedSpec.slotCount - 1),
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
