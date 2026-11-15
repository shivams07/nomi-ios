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
    for symbol in CategoryEditorLogic.iconChoices {
      XCTAssertNotEqual(PaletteSlotOptions.iconName(forSymbol: symbol), symbol, "no name for \(symbol)")
    }
  }

  /// The colour row is hidden (S13), so an edit writes back the slot the
  /// category already has. Every one of the seven survives a save.
  func testEditKeepsTheSavedSlot() {
    for slot in PaletteSlotOptions.all {
      XCTAssertEqual(PaletteSlotOptions.slotOnSave(editing: slot), slot)
    }
  }

  /// A new category has no colour to keep, so it gets slot 0.
  func testNewCategoryGetsSlotZero() {
    XCTAssertEqual(PaletteSlotOptions.slotOnSave(editing: nil), 0)
  }

  /// A stored slot outside the seven cannot be changed from the editor any
  /// more, so a save would fail with a message the user cannot act on. It
  /// falls back to slot 0 instead.
  func testOutOfRangeSlotFallsBackToSlotZero() {
    XCTAssertEqual(PaletteSlotOptions.slotOnSave(editing: 7), 0)
    XCTAssertEqual(PaletteSlotOptions.slotOnSave(editing: -1), 0)
  }
}
