import XCTest
@testable import NomiUI

final class PaletteSlotOptionsTests: XCTestCase {
  /// Done-when (v5): "the category editor offers exactly seven slots and no
  /// arbitrary colour well."
  func testOffersExactlySevenSlots() {
    XCTAssertEqual(PaletteSlotOptions.all.count, 7)
  }

  func testSlotsAreZeroIndexedThroughSix() {
    XCTAssertEqual(PaletteSlotOptions.all, Array(0..<7))
  }

  /// VoiceOver names: one per slot, in palette order, so a swatch is never
  /// announced as an unnamed colour.
  func testEverySlotHasAColourName() {
    XCTAssertEqual(PaletteSlotOptions.slotNames.count, PaletteSlotOptions.all.count)
    XCTAssertEqual(PaletteSlotOptions.colourName(forSlot: 0), "Orange")
    XCTAssertEqual(PaletteSlotOptions.colourName(forSlot: 6), "Red")
  }

  func testOutOfRangeSlotIsNamedOther() {
    XCTAssertEqual(PaletteSlotOptions.colourName(forSlot: 7), "Other")
  }

  /// Every icon in the grid has a spoken name, not its raw SF Symbol string.
  func testEveryIconChoiceHasAName() {
    for symbol in PaletteSlotOptions.symbolChoices {
      XCTAssertNotEqual(PaletteSlotOptions.iconName(forSymbol: symbol), symbol, "no name for \(symbol)")
    }
  }
}
