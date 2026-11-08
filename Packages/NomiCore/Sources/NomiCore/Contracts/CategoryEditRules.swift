import Foundation

/// Why a category edit was refused. The editor shows the reason; nothing
/// branches on the case beyond that.
public enum CategoryUpdateError: Error, Equatable, Sendable {
  /// The conformer does not edit categories. Nothing in the tree throws this
  /// today: `CategoryStore.update` is a strict requirement with no default, and
  /// `SwiftDataCategoryStore` throws the other cases. `CategoryEditorLogic` still
  /// maps this case to the generic save line, so a conformer that refuses with
  /// it gets that line.
  case notSupported
  /// No category row has this id. `Category.uncategorizedID` lands here too:
  /// it is a display sentinel with no row, and it must not be editable.
  case notFound(UUID)
  /// Empty once surrounding and internal whitespace is removed.
  case emptyName
  /// Another category already has this name, compared without regard to case
  /// or whitespace. Carries the normalised name that was refused.
  case duplicateName(String)
  /// Outside `0..<CategoryEditRules.paletteSlotCount`. Refused, not clamped:
  /// an edit should store what the user chose, or nothing.
  case paletteSlotOutOfRange(Int)
  /// Not a shape an SF Symbol name can take. See `isValidSymbolName`.
  case invalidSymbolName(String)
}

/// The rules a category edit must pass, as pure functions, so every conformer
/// applies the same ones and they can be tested without a container.
///
/// These are conservative choices where the specs are silent on the store
/// side. The editor specifies the fields (name, seven colours, an icon grid)
/// and the delete rule, and nothing about what the store refuses. Each rule
/// here is one a bad write would otherwise slip past.
public enum CategoryEditRules {
  /// The number of palette hues. `NomiUI` owns the colours and `NomiCore` owns
  /// the index (the seed comment in NomiApp says so). It must equal
  /// `CategorySeedSpec.slotCount` in NomiApp; a NomiApp test pins that.
  public static let paletteSlotCount = 7

  /// The name as it is stored: surrounding whitespace removed, and every run of
  /// internal whitespace (spaces, tabs, newlines) collapsed to one space.
  public static func normalizedName(_ raw: String) -> String {
    raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  /// Checks an edit and returns the name to store. Throws before anything is
  /// written, so a refused edit leaves the row exactly as it was.
  ///
  /// - Parameter otherNames: the names of every category except the one being
  ///   edited. Keeping its own name, in any case, must pass, so the caller
  ///   leaves the edited row out of this list.
  public static func validate(
    name: String,
    symbolName: String,
    paletteSlot: Int,
    otherNames: [String]
  ) throws -> String {
    let stored = normalizedName(name)
    guard !stored.isEmpty else { throw CategoryUpdateError.emptyName }

    let key = comparisonKey(stored)
    if otherNames.contains(where: { comparisonKey($0) == key }) {
      throw CategoryUpdateError.duplicateName(stored)
    }

    guard (0..<paletteSlotCount).contains(paletteSlot) else {
      throw CategoryUpdateError.paletteSlotOutOfRange(paletteSlot)
    }

    guard isValidSymbolName(symbolName) else {
      throw CategoryUpdateError.invalidSymbolName(symbolName)
    }

    return stored
  }

  /// Whether `name` has the shape of an SF Symbol name: one or more
  /// dot-separated segments, each a non-empty run of ASCII letters or digits.
  /// `fork.knife`, `tag` and `list.bullet.rectangle` pass. Whitespace,
  /// hyphens, slashes, empty segments and leading or trailing dots do not.
  ///
  /// `NomiCore` is Foundation-only and cannot ask UIKit whether a symbol
  /// exists, so this rejects what cannot be a symbol name. It does not prove
  /// that the name renders.
  public static func isValidSymbolName(_ name: String) -> Bool {
    guard !name.isEmpty else { return false }
    return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { segment in
      !segment.isEmpty && segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
  }

  /// The key two names are compared by: normalised, then lowercased.
  static func comparisonKey(_ name: String) -> String {
    normalizedName(name).lowercased()
  }
}
