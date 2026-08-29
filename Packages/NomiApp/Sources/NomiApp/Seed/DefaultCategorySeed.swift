import Foundation
import NomiCore
import SwiftData

/// One seeded category, as a value. Deliberately not a `@Model`: `swift test`
/// cannot construct a SwiftData `@Model` in this CI at all (see
/// `NomiCore/Support/InMemoryModelContainer.swift`), so the *content* of the
/// seed — the count, the slots, the ids, the system flag — has to live on this
/// side of the line or nothing about it is ever executed by a test.
public struct CategorySeedSpec: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let name: String
  public let symbolName: String
  /// 0...6. `NomiUI/Design/**` owns the hues; `NomiCore` owns the index
  /// (§2.6). Park never writes a colour.
  public let paletteSlot: Int
  public let sortIndex: Int

  public init(id: UUID, name: String, symbolName: String, paletteSlot: Int, sortIndex: Int) {
    self.id = id
    self.name = name
    self.symbolName = symbolName
    self.paletteSlot = paletteSlot
    self.sortIndex = sortIndex
  }
}

/// The India default category set (design §"v5 ADDS", U8 block). Fourteen
/// categories, `isSystem = true`, each carrying a `paletteSlot` and never a hex.
///
/// **The ids are fixed constants, and that is load-bearing.** Seeding is
/// idempotent by *identity*, not by name. `Category` is a SwiftData model on a
/// CloudKit-backed store, so two devices signed into the same iCloud account
/// each run this seed on their own first launch. Generated ids would give the
/// user twenty-eight categories the moment those two devices synced — the same
/// class of failure as R5, with no reconcile pass to clean it up. Matching on
/// `name` instead would break the moment anyone renames one.
///
/// Slots repeat past seven by design: `slot = index % 7`. A slot is a hue, not
/// an identity (§2.6), and `CategoryPalette` is a validated ordered seven that a
/// generated eighth hue would invalidate.
public enum DefaultCategorySeed {

  /// `00000000-0000-0000-0000-0000000010NN`. Obviously synthetic, ordered, and
  /// clear of `Category.uncategorizedID` (`...0001`), which is a *display*
  /// sentinel for a nil `categoryID` and must never be seeded as a real row —
  /// seeding it would make "Uncategorized" assignable and rule-targetable.
  static func seedID(_ ordinal: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-0000000010%02d", ordinal))!
  }

  /// Order is the spec's order, and it is also `sortIndex`, so the category
  /// list reads the way the design lists it rather than alphabetically.
  static let names: [(String, String)] = [
    ("UPI & Food Delivery", "fork.knife"),
    ("Ride-hailing", "car.fill"),
    ("Recharge & Utilities", "bolt.fill"),
    ("Rent", "house.fill"),
    ("EMI & Loan", "building.columns.fill"),
    ("SIP & Investments", "chart.line.uptrend.xyaxis"),
    ("Insurance", "shield.fill"),
    ("ATM Cash", "banknote.fill"),
    ("P2P Transfer", "arrow.left.arrow.right"),
    ("Shopping", "bag.fill"),
    ("Groceries", "cart.fill"),
    ("Health", "cross.case.fill"),
    ("Salary & Income", "arrow.down.circle.fill"),
    ("Other", "tag"),
  ]

  public static let specs: [CategorySeedSpec] = names.enumerated().map { index, entry in
    CategorySeedSpec(
      id: seedID(index + 1),
      name: entry.0,
      symbolName: entry.1,
      paletteSlot: index % CategorySeedSpec.slotCount,
      sortIndex: index
    )
  }

  /// The specs not already present, given the ids the store already holds.
  ///
  /// Pure, and separated from the insert for one reason: this is the part that
  /// decides, and it is the part a test can run. Passing an id set rather than a
  /// `ModelContext` is what keeps it that way.
  public static func missing(existingIDs: Set<UUID>) -> [CategorySeedSpec] {
    specs.filter { !existingIDs.contains($0.id) }
  }
}

extension CategorySeedSpec {
  /// Mirrors `CategoryPalette.slots.count`. Duplicated as an integer rather than
  /// read from `NomiUI` because the seed is `NomiCore`-shaped data and reaching
  /// into the design package for a count would invert the dependency the whole
  /// §2.6 split exists to establish. `DefaultCategorySeedTests` pins it.
  static let slotCount = 7
}

// MARK: - Applying the seed
//
// Below this line touches `@Model` and is therefore compile-verified only, the
// same standing `SwiftDataPipelineStore` has. Keep it thin: everything that
// decides anything is above.

extension DefaultCategorySeed {
  /// Inserts whatever is missing. Safe to call on every launch, and it is
  /// called on every launch — a category deleted by a future migration, or a
  /// store restored from a backup that predates a seed addition, heals here.
  ///
  /// It does **not** rewrite existing rows. A user who renamed "Other" keeps
  /// their name; a palette change in `Design/**` needs no re-seed because the
  /// row stores a slot, not a colour.
  @MainActor
  static func apply(in context: ModelContext) throws {
    let existing = try context.fetch(FetchDescriptor<NomiCore.Category>())
    let existingIDs = Set(existing.map(\.id))

    for spec in missing(existingIDs: existingIDs) {
      context.insert(
        NomiCore.Category(
          id: spec.id,
          name: spec.name,
          symbolName: spec.symbolName,
          paletteSlot: spec.paletteSlot,
          isSystem: true,
          sortIndex: spec.sortIndex
        )
      )
    }

    if context.hasChanges {
      try context.save()
    }
  }
}
