import Foundation
import NomiCore
import XCTest

@testable import NomiPreview

/// `FakeCategoryStore.create` applies the rules `SwiftDataCategoryStore.create`
/// applies, so a preview refuses what the app refuses. Nothing is appended on
/// refusal.
///
/// XCTest, `@MainActor`, as the fake is.
@MainActor
final class FakeCategoryStoreCreateTests: XCTestCase {

  private func makeFake() -> FakeCategoryStore {
    FakeCategoryStore(categories: [
      NomiCore.Category(name: "Food & Dining", symbolName: "fork.knife", paletteSlot: 0, isSystem: true, sortIndex: 0),
      NomiCore.Category(name: "Travel", symbolName: "car", paletteSlot: 2, isSystem: false, sortIndex: 1),
    ])
  }

  func testAUniqueCreateIsAppended() throws {
    let fake = makeFake()

    let created = try fake.create(name: "Pets", symbolName: "heart", paletteSlot: 3)

    XCTAssertEqual(created.name, "Pets")
    XCTAssertEqual(fake.categories.count, 3)
    XCTAssertEqual(fake.categories.last?.id, created.id)
  }

  func testTheStoredNameIsTheNormalisedName() throws {
    let fake = makeFake()

    let created = try fake.create(name: "  Home \n Office ", symbolName: "house", paletteSlot: 4)

    XCTAssertEqual(created.name, "Home Office")
    XCTAssertEqual(fake.categories.last?.name, "Home Office")
  }

  func testACaseInsensitiveDuplicateIsRefusedAndNothingIsAppended() {
    let fake = makeFake()

    XCTAssertThrowsError(try fake.create(name: "food & DINING", symbolName: "tag", paletteSlot: 5)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("food & DINING"))
    }

    XCTAssertEqual(fake.categories.count, 2)
  }

  func testAWhitespacePaddedDuplicateIsRefusedAndNothingIsAppended() {
    let fake = makeFake()

    XCTAssertThrowsError(try fake.create(name: " Travel ", symbolName: "car", paletteSlot: 2)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .duplicateName("Travel"))
    }

    XCTAssertEqual(fake.categories.count, 2)
  }

  func testAnEmptyNameIsRefusedAndNothingIsAppended() {
    let fake = makeFake()

    XCTAssertThrowsError(try fake.create(name: " \n ", symbolName: "tag", paletteSlot: 0)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .emptyName)
    }

    XCTAssertEqual(fake.categories.count, 2)
  }

  func testASlotOutsideTheSevenHuesIsRefusedNotClampedAndNothingIsAppended() {
    let fake = makeFake()

    XCTAssertThrowsError(try fake.create(name: "Pets", symbolName: "heart", paletteSlot: 7)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .paletteSlotOutOfRange(7))
    }

    XCTAssertEqual(fake.categories.count, 2)
  }

  func testAnInvalidSymbolIsRefusedAndNothingIsAppended() {
    let fake = makeFake()

    XCTAssertThrowsError(try fake.create(name: "Pets", symbolName: "air plane", paletteSlot: 3)) { error in
      XCTAssertEqual(error as? CategoryUpdateError, .invalidSymbolName("air plane"))
    }

    XCTAssertEqual(fake.categories.count, 2)
  }
}
