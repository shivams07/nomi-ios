import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// The India default set is *content*, and content is exactly what a compiler
/// cannot check. Most of this file asserts the specs, which need no container;
/// the one test of `DefaultCategorySeed.apply` builds one, which XCTest can and
/// swift-testing cannot (see `InMemoryModelContainer`'s note in NomiCore).
final class DefaultCategorySeedTests: XCTestCase {

  /// W1-1. `ReferenceDataReconciler` keeps the earliest-created copy of a
  /// duplicated id, so a seeded row must say when it was created. An undated
  /// one is stamped by the reconciler instead — a pass later, and at the time
  /// of that pass rather than of the seed.
  @MainActor
  func testASeededCategoryCarriesItsCreationDate() throws {
    let container = try ModelContainer(
      for: NomiModelContainer.schema,
      configurations: [
        ModelConfiguration(
          schema: NomiModelContainer.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ])
    let context = container.mainContext

    try DefaultCategorySeed.apply(in: context)

    let seeded = try context.fetch(FetchDescriptor<NomiCore.Category>())
    XCTAssertEqual(seeded.count, DefaultCategorySeed.specs.count)
    XCTAssertTrue(seeded.allSatisfy { $0.createdAt != nil })
  }

  /// The fourteen, verbatim from the design's U8 block, in its order.
  private static let expectedNames = [
    "UPI & Food Delivery",
    "Ride-hailing",
    "Recharge & Utilities",
    "Rent",
    "EMI & Loan",
    "SIP & Investments",
    "Insurance",
    "ATM Cash",
    "P2P Transfer",
    "Shopping",
    "Groceries",
    "Health",
    "Salary & Income",
    "Other",
  ]

  func testSeedsExactlyTheFourteenNamedCategoriesInOrder() {
    XCTAssertEqual(DefaultCategorySeed.specs.map(\.name), Self.expectedNames)
  }

  func testSortIndexIsTheDesignsOrder() {
    XCTAssertEqual(DefaultCategorySeed.specs.map(\.sortIndex), Array(0..<14))
  }

  /// §2.6: `paletteSlot`, never a hex. `NomiUI/Design/**` owns the seven hues
  /// and a slot outside 0...6 resolves to the grey Other treatment, so a seeded
  /// category landing there would be a colourless category by accident.
  func testEveryPaletteSlotIsWithinTheSevenSlotPalette() {
    for spec in DefaultCategorySeed.specs {
      XCTAssertTrue(
        (0..<CategorySeedSpec.slotCount).contains(spec.paletteSlot),
        "\(spec.name) has slot \(spec.paletteSlot)"
      )
    }
  }

  /// "Slots repeat past seven by design; slot is a hue, not an identity."
  func testSlotsRepeatEverySeven() {
    XCTAssertEqual(
      DefaultCategorySeed.specs.map(\.paletteSlot),
      (0..<14).map { $0 % 7 }
    )
  }

  func testIDsAreUnique() {
    XCTAssertEqual(Set(DefaultCategorySeed.specs.map(\.id)).count, DefaultCategorySeed.specs.count)
  }

  /// `Category.uncategorizedID` is a display sentinel for a nil `categoryID`.
  /// Seeding a row with it would make "Uncategorized" a real, assignable,
  /// rule-targetable category — and every aggregate that folds nil into that id
  /// would then double-count against it.
  func testNoSeedCollidesWithTheUncategorizedSentinel() {
    XCTAssertFalse(DefaultCategorySeed.specs.map(\.id).contains(NomiCore.Category.uncategorizedID))
  }

  /// The ids are constants rather than generated, so that a second device
  /// running the same seed produces the same fourteen rows instead of fourteen
  /// more. Pinning the first and last catches an edit that renumbers them.
  func testIDsAreStableConstants() {
    XCTAssertEqual(
      DefaultCategorySeed.specs.first?.id,
      UUID(uuidString: "00000000-0000-0000-0000-000000001001")
    )
    XCTAssertEqual(
      DefaultCategorySeed.specs.last?.id,
      UUID(uuidString: "00000000-0000-0000-0000-000000001014")
    )
  }

  func testEverySeedIsMissingFromAnEmptyStore() {
    XCTAssertEqual(DefaultCategorySeed.missing(existingIDs: []).count, 14)
  }

  /// The seed runs on every launch. The second launch must insert nothing.
  func testNothingIsMissingOnceEverySeedIsPresent() {
    let all = Set(DefaultCategorySeed.specs.map(\.id))
    XCTAssertTrue(DefaultCategorySeed.missing(existingIDs: all).isEmpty)
  }

  /// A store restored from a backup predating a seed addition, or one row
  /// deleted by a future migration, heals on the next launch — and only that
  /// row is reinserted.
  func testOnlyTheAbsentSeedIsReinserted() {
    var present = Set(DefaultCategorySeed.specs.map(\.id))
    let removed = DefaultCategorySeed.seedID(5)
    present.remove(removed)

    let missing = DefaultCategorySeed.missing(existingIDs: present)
    XCTAssertEqual(missing.count, 1)
    XCTAssertEqual(missing.first?.id, removed)
  }

  /// User-created categories are in the store too and must not make the seed
  /// think one of its own is present.
  func testUnrelatedIDsDoNotSatisfyTheSeed() {
    XCTAssertEqual(DefaultCategorySeed.missing(existingIDs: [UUID(), UUID()]).count, 14)
  }
}
