import Foundation

/// Splits the bundled licence text into blocks for `LicensesScreen` (L1).
///
/// One `Text` over the whole file draws nothing once its laid-out height passes
/// what the renderer can hold, which happens at accessibility sizes (AX3 and up).
/// Each block is a run of whole lines, so no block is taller than the bound and
/// no word is cut.
enum LicensesLogic {
  /// The most characters one block may hold. Lines are never split, so a block
  /// can exceed this only when a single line is longer than the bound.
  static let maxCharactersPerBlock = 2_000

  /// The text as consecutive blocks. Joining the blocks with "\n" gives back
  /// `text` exactly, so every line appears once, in order.
  static func blocks(
    for text: String,
    maxCharactersPerBlock: Int = LicensesLogic.maxCharactersPerBlock
  ) -> [String] {
    // Red-first stub: the current main behaviour, one block for the whole text.
    [text]
  }
}
