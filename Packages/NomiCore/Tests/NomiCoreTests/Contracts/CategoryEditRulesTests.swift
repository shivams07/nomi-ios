import Foundation
import Testing
@testable import NomiCore

struct CategoryEditRulesTests {

  // MARK: name

  @Test func normalisedNameTrimsAndCollapsesInternalWhitespace() {
    #expect(CategoryEditRules.normalizedName("  Food \t &\n\n  Dining  ") == "Food & Dining")
    #expect(CategoryEditRules.normalizedName("Shopping") == "Shopping")
    #expect(CategoryEditRules.normalizedName(" \n\t ") == "")
  }

  @Test func emptyAndWhitespaceOnlyNamesAreRefused() throws {
    for raw in ["", "   ", "\n\t \n"] {
      #expect(throws: CategoryUpdateError.emptyName) {
        try CategoryEditRules.validate(name: raw, symbolName: "tag", paletteSlot: 0, otherNames: [])
      }
    }
  }

  @Test func aNameDifferingOnlyByCaseOrWhitespaceIsADuplicate() throws {
    let others = ["Food & Dining"]
    #expect(throws: CategoryUpdateError.duplicateName("food & dining")) {
      try CategoryEditRules.validate(name: "food & dining", symbolName: "tag", paletteSlot: 0, otherNames: others)
    }
    #expect(throws: CategoryUpdateError.duplicateName("Food & Dining")) {
      try CategoryEditRules.validate(name: "  Food   &  Dining ", symbolName: "tag", paletteSlot: 0, otherNames: others)
    }
  }

  @Test func aDistinctNameIsStoredNormalised() throws {
    let stored = try CategoryEditRules.validate(
      name: "  Eating   Out ", symbolName: "fork.knife", paletteSlot: 2, otherNames: ["Food & Dining"])
    #expect(stored == "Eating Out")
  }

  @Test func keepingOwnNameIsAllowedBecauseTheEditedRowIsNotInOtherNames() throws {
    // The caller leaves the edited row out of `otherNames`, so an edit that
    // only changes case passes. Naming the row's own name in `otherNames`
    // is the caller's bug, and this test pins that the rule itself would
    // refuse it.
    let stored = try CategoryEditRules.validate(
      name: "TRAVEL", symbolName: "car", paletteSlot: 2, otherNames: ["Shopping"])
    #expect(stored == "TRAVEL")
    #expect(throws: CategoryUpdateError.duplicateName("TRAVEL")) {
      try CategoryEditRules.validate(name: "TRAVEL", symbolName: "car", paletteSlot: 2, otherNames: ["travel"])
    }
  }

  // MARK: palette slot

  @Test func paletteSlotsZeroThroughSixAreAccepted() throws {
    for slot in 0...6 {
      _ = try CategoryEditRules.validate(name: "X", symbolName: "tag", paletteSlot: slot, otherNames: [])
    }
    #expect(CategoryEditRules.paletteSlotCount == 7)
  }

  @Test func paletteSlotsOutsideTheSevenHuesAreRefusedNotClamped() {
    for slot in [-1, 7, 8, Int.max] {
      #expect(throws: CategoryUpdateError.paletteSlotOutOfRange(slot)) {
        try CategoryEditRules.validate(name: "X", symbolName: "tag", paletteSlot: slot, otherNames: [])
      }
    }
  }

  // MARK: symbol name

  @Test func symbolNamesShapedLikeSFSymbolsAreAccepted() {
    for name in ["tag", "fork.knife", "play.tv", "list.bullet.rectangle", "person.crop.circle.badge.checkmark", "1.circle"] {
      #expect(CategoryEditRules.isValidSymbolName(name), "\(name) should be valid")
    }
  }

  @Test func symbolNamesThatCannotBeSymbolNamesAreRefused() {
    for name in ["", " tag", "tag ", "fork knife", "fork\nknife", ".bag", "bag.", "bag..x", "bag/x", "bag-x", "bag_x", "emoji🍔"] {
      #expect(!CategoryEditRules.isValidSymbolName(name), "\(name.debugDescription) should be invalid")
    }
  }

  @Test func anInvalidSymbolIsRefusedWhateverTheName() {
    #expect(throws: CategoryUpdateError.invalidSymbolName("fork knife")) {
      try CategoryEditRules.validate(name: "Food", symbolName: "fork knife", paletteSlot: 0, otherNames: [])
    }
  }

  // MARK: order of checks

  @Test func theNameIsCheckedBeforeTheSlotAndTheSymbol() {
    // All three are wrong. The name error is the one reported, so the editor
    // shows the first thing the user must fix.
    #expect(throws: CategoryUpdateError.emptyName) {
      try CategoryEditRules.validate(name: " ", symbolName: "bad symbol", paletteSlot: 99, otherNames: [])
    }
  }
}

/// A conformer that never implements `update`. The protocol default must throw
/// rather than succeed silently, so an edit can never vanish unreported.
@MainActor
private final class StoreWithoutUpdate: CategoryStore {
  func create(name: String, symbolName: String, paletteSlot: Int) throws -> NomiCore.Category {
    NomiCore.Category(name: name, symbolName: symbolName, paletteSlot: paletteSlot)
  }
  func rename(_ id: UUID, to name: String) throws {}
  func delete(_ id: UUID) throws {}
}

@MainActor
struct CategoryStoreUpdateDefaultTests {

  @Test func aConformerThatDoesNotImplementUpdateThrowsNotSupported() {
    let store: CategoryStore = StoreWithoutUpdate()
    #expect(throws: CategoryUpdateError.notSupported) {
      try store.update(UUID(), name: "Food", symbolName: "tag", paletteSlot: 0)
    }
  }
}
