import Foundation

/// Splits the bundled licence text into blocks for `LicensesScreen` (L1).
///
/// One `Text` over the whole file draws nothing once its laid-out height passes
/// what the renderer can hold. Measured in a test host, a single Text about
/// 61,000 pt tall drew and one about 92,000 pt tall drew nothing, which is where
/// AX3 falls. Each block is a run of whole lines, so no word is cut, and the
/// character bound keeps every block far below that height at every size.
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
    var blocks: [String] = []
    var pending: [String] = []
    var pendingCount = 0
    for line in text.components(separatedBy: "\n") {
      let joinCost = pending.isEmpty ? 0 : 1
      if !pending.isEmpty, pendingCount + joinCost + line.count > maxCharactersPerBlock {
        blocks.append(pending.joined(separator: "\n"))
        pending = []
        pendingCount = 0
      }
      pendingCount += pending.isEmpty ? line.count : line.count + 1
      pending.append(line)
    }
    blocks.append(pending.joined(separator: "\n"))
    return blocks
  }
}
