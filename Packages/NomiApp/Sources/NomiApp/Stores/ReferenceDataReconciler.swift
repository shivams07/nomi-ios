import Foundation
import NomiCore
import SwiftData

/// The reference-data pass, as `AppSyncCoordinator` sees it.
///
/// A protocol so the scheduling tests can count reconciles without a container;
/// `ReferenceDataReconciler` is the only real conformer.
@MainActor
public protocol ReferenceDataReconciling: AnyObject, Sendable {
  /// Returns how many rows were removed.
  @discardableResult func run() throws -> Int
}

/// R5 for the rows that are not transactions (H1).
///
/// CloudKit forbids unique constraints. Two devices each running
/// `DefaultCategorySeed` and `DefaultRuleSeed` on their own first launch each
/// insert the same fixed ids, and sync delivers both copies. Nothing collapsed
/// them — `IngestPipeline.reconcile()` only ever looks at `Transaction` — so the
/// user got two of every category and every seeded rule. Budgets double the
/// same way, grouped by category rather than by id, because a budget's id is
/// random.
///
/// **The survivor is the row with the earliest `createdAt`, and nothing else
/// decides it.** Fetch order and `persistentModelID` are local to the device
/// reading them; `createdAt` is the one value every device sees the same once
/// sync settles, so every device keeps the same row, deletes the same others,
/// and none deletes the row another device kept.
///
/// `Category.createdAt` arrived after the seed, so rows written before it read
/// `nil`. Those are stamped on one pass and collapsed on a later one, never in
/// the pass that stamped them: a group is collapsed only when every member
/// already had a date when the pass began.
///
/// Rows are deleted through the context, never through `CategoryStore.delete`,
/// which takes a category's rules and budgets with it. Removing a duplicate must
/// not remove the user's rules.
@MainActor
public final class ReferenceDataReconciler: ReferenceDataReconciling {
  private let context: ModelContext
  private let coordinator: WriteCoordinator
  private let now: () -> Date

  /// The gap between two dates stamped in one pass.
  ///
  /// Not zero, on purpose. Stamping every undated row with one shared `now()`
  /// gives two undated copies of one id the *same* date — which manufactures
  /// exactly the tie the survivor rule has no answer for. The next pass would
  /// then keep whichever copy the fetch returned first, and two devices could
  /// each keep a different one and each delete the other.
  static let stampSpacing: TimeInterval = 0.001

  public init(
    context: ModelContext,
    coordinator: WriteCoordinator,
    now: @escaping () -> Date = { Date() }
  ) {
    self.context = context
    self.coordinator = coordinator
    self.now = now
  }

  /// Stamps, collapses, saves once. `coordinator.didWrite()` fires iff a row was
  /// removed: a pass that only stamped dates changed nothing anything reads.
  ///
  /// A failed save rolls the context back. It is `mainContext` — shared with
  /// every store, and autosaving — so deletes left pending would be persisted
  /// by whatever saved next.
  @discardableResult
  public func run() throws -> Int {
    do {
      let removed = try collapseCategories() + collapseRules() + collapseBudgets()
      if context.hasChanges {
        try context.save()
      }
      if removed > 0 {
        coordinator.didWrite()
      }
      return removed
    } catch {
      context.rollback()
      throw error
    }
  }

  private func collapseCategories() throws -> Int {
    let rows = try context.fetch(FetchDescriptor<NomiCore.Category>())

    let undated = rows.filter { $0.createdAt == nil }
    let undatedIDs = Set(undated.map(\.id))
    let stamp = now()
    for (offset, row) in undated.enumerated() {
      row.createdAt = stamp.addingTimeInterval(Double(offset) * Self.stampSpacing)
    }

    let seeds = Dictionary(
      DefaultCategorySeed.specs.map { ($0.id, CategoryValues(spec: $0)) },
      uniquingKeysWith: { first, _ in first }
    )

    var removed = 0
    for (id, group) in Dictionary(grouping: rows, by: { $0.id }) where group.count > 1 {
      guard !undatedIDs.contains(id) else { continue }
      removed += collapse(
        group,
        seed: seeds[id],
        createdAt: { $0.createdAt },
        values: { CategoryValues($0) },
        carry: { $0.write(to: $1) }
      )
    }
    return removed
  }

  private func collapseRules() throws -> Int {
    let rows = try context.fetch(FetchDescriptor<Rule>())
    let seeds = Dictionary(
      DefaultRuleSeed.specs.map { ($0.id, RuleValues(spec: $0)) },
      uniquingKeysWith: { first, _ in first }
    )

    var removed = 0
    for (id, group) in Dictionary(grouping: rows, by: { $0.id }) where group.count > 1 {
      removed += collapse(
        group,
        seed: seeds[id],
        createdAt: { $0.createdAt },
        values: { RuleValues($0) },
        carry: { $0.write(to: $1) }
      )
    }
    return removed
  }

  /// Grouped by `categoryID`. There is no seed, so nothing is ever carried and
  /// the value compared is immaterial. The earliest row is also the one
  /// `SwiftDataBudgetStore` has been reading and editing all along — it picks
  /// the oldest — so the survivor is the budget the user actually set.
  private func collapseBudgets() throws -> Int {
    let rows = try context.fetch(FetchDescriptor<Budget>())

    var removed = 0
    for group in Dictionary(grouping: rows, by: { $0.categoryID }).values where group.count > 1 {
      removed += collapse(
        group,
        seed: nil,
        createdAt: { $0.createdAt },
        values: { $0.amountMinor },
        carry: { _, _ in }
      )
    }
    return removed
  }

  /// Builds the value rows, asks `ReferenceDataResolution`, applies the answer.
  /// Returns how many rows it deleted.
  private func collapse<Row: PersistentModel, Values: Equatable>(
    _ group: [Row],
    seed: Values?,
    createdAt: (Row) -> Date?,
    values: (Row) -> Values,
    carry: (Values, Row) -> Void
  ) -> Int {
    let members = group.enumerated().map { index, row in
      ReferenceRow(index: index, createdAt: createdAt(row), values: values(row))
    }
    guard let outcome = ReferenceDataResolution.collapse(members, seed: seed) else { return 0 }

    if let carried = outcome.carried {
      carry(carried, group[outcome.survivor])
    }
    for index in outcome.losers {
      context.delete(group[index])
    }
    return outcome.losers.count
  }
}

// MARK: - The rule, over values

/// One member of a duplicate group, as a value.
struct ReferenceRow<Values: Equatable>: Equatable {
  /// Where the member sits in the group as fetched. It identifies the member
  /// and nothing more: it never breaks a tie and never chooses a survivor.
  let index: Int
  let createdAt: Date?
  let values: Values
}

struct ReferenceCollapse<Values: Equatable>: Equatable {
  let survivor: Int
  let losers: [Int]
  /// Values the survivor takes before the losers are deleted, if any.
  let carried: Values?
}

/// Pure. Everything that decides which row survives is here.
enum ReferenceDataResolution {

  /// `nil` for a group of one, and for a group with any undated member — stamp
  /// first, collapse on a later pass.
  ///
  /// **Carried edits.** When the survivor still equals its seed and a loser does
  /// not, that loser holds an edit the user made on the other device — a rename,
  /// a retarget — and the survivor takes it before the loser goes. If several
  /// losers differ, the earliest of them is taken, by the same rule that chose
  /// the survivor. A survivor that already differs from its seed holds an edit
  /// of its own and keeps it.
  ///
  /// Two members with one `createdAt` are a tie this does not break: the first
  /// of them in `group` is kept. That is two writes in the same instant on two
  /// devices, and `ReferenceDataReconciler.stampSpacing` is what keeps it from
  /// being manufactured locally.
  static func collapse<Values: Equatable>(
    _ group: [ReferenceRow<Values>],
    seed: Values?
  ) -> ReferenceCollapse<Values>? {
    guard group.count > 1, group.allSatisfy({ $0.createdAt != nil }) else { return nil }

    let earliestFirst: (ReferenceRow<Values>, ReferenceRow<Values>) -> Bool = {
      ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture)
    }
    guard let survivor = group.min(by: earliestFirst) else { return nil }
    let losers = group.filter { $0.index != survivor.index }

    var carried: Values?
    if let seed, survivor.values == seed {
      carried = losers.filter { $0.values != seed }.min(by: earliestFirst)?.values
    }

    return ReferenceCollapse(
      survivor: survivor.index,
      losers: losers.map(\.index),
      carried: carried
    )
  }
}

// MARK: - What a user can edit, per entity

/// The category fields the seed sets and a user can change.
struct CategoryValues: Equatable {
  var name: String
  var symbolName: String
  var paletteSlot: Int
  var sortIndex: Int
}

extension CategoryValues {
  init(_ row: NomiCore.Category) {
    self.init(
      name: row.name, symbolName: row.symbolName, paletteSlot: row.paletteSlot,
      sortIndex: row.sortIndex)
  }

  init(spec: CategorySeedSpec) {
    self.init(
      name: spec.name, symbolName: spec.symbolName, paletteSlot: spec.paletteSlot,
      sortIndex: spec.sortIndex)
  }

  func write(to row: NomiCore.Category) {
    row.name = name
    row.symbolName = symbolName
    row.paletteSlot = paletteSlot
    row.sortIndex = sortIndex
  }
}

/// The rule fields the seed sets and a user can change.
struct RuleValues: Equatable {
  var pattern: String
  var categoryID: UUID
  var isEnabled: Bool
  var priority: Int
}

extension RuleValues {
  init(_ rule: Rule) {
    self.init(
      pattern: rule.pattern, categoryID: rule.categoryID, isEnabled: rule.isEnabled,
      priority: rule.priority)
  }

  /// A seeded rule is inserted enabled.
  init(spec: RuleSeedSpec) {
    self.init(
      pattern: spec.pattern, categoryID: spec.categoryID, isEnabled: true,
      priority: spec.priority)
  }

  func write(to rule: Rule) {
    rule.pattern = pattern
    rule.categoryID = categoryID
    rule.isEnabled = isEnabled
    rule.priority = priority
  }
}
