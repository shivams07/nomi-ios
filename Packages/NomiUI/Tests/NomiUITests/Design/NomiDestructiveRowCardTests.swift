import Foundation
import XCTest

/// NomiDestructiveRow draws its own card (F2a, D21), so no call site may put a
/// card around it. This reads the NomiUI and NomiApp sources and fails when a
/// row sits inside a `.nomiCard` container, or carries one as a modifier.
///
/// It is a line-based check, not a Swift parser: it follows brace depth and
/// the modifier chain after each closing brace. Good enough for the call
/// shapes in this repo, and it fails loudly on the shape it was written for.
final class NomiDestructiveRowCardTests: XCTestCase {
  func testNoCallSiteWrapsDestructiveRowInACard() throws {
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // Design
      .deletingLastPathComponent() // NomiUITests
      .deletingLastPathComponent() // Tests
      .deletingLastPathComponent() // NomiUI (package root)
      .deletingLastPathComponent() // Packages
    let roots = [
      packages.appendingPathComponent("NomiUI/Sources"),
      packages.appendingPathComponent("NomiApp/Sources"),
    ]

    var violations: [String] = []
    var scanned = 0
    for root in roots {
      guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
        XCTFail("cannot enumerate \(root.path)")
        continue
      }
      for case let url as URL in files where url.pathExtension == "swift" {
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: "\n")
        scanned += 1
        for index in lines.indices where isCallSite(lines[index]) {
          if let found = wrappingCard(lines: lines, callIndex: index) {
            violations.append("\(url.lastPathComponent):\(index + 1) wrapped by .nomiCard at line \(found + 1)")
          }
        }
      }
    }

    XCTAssertGreaterThan(scanned, 100, "scanned too few files: \(scanned)")
    XCTAssertEqual(violations, [], "NomiDestructiveRow must not sit in a card; it has its own")
  }

  // MARK: - Helpers

  /// A live call, not a doc comment or the declaration itself.
  private func isCallSite(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("public struct") else { return false }
    return trimmed.contains("NomiDestructiveRow(")
  }

  /// The line of a `.nomiCard` that wraps the call: a card chained onto the
  /// row itself, or onto any block that encloses it, up to 8 levels out.
  private func wrappingCard(lines: [String], callIndex: Int) -> Int? {
    var start = callIndex
    for _ in 0..<8 {
      guard let closing = closingLine(lines, from: start) else { return nil }
      if let card = cardChained(lines, closingLine: closing) {
        return card
      }
      guard let opener = enclosingOpener(lines, before: start) else { return nil }
      start = opener
    }
    return nil
  }

  /// The line that closes the block opened on or after `start`: brace depth
  /// returns to zero after the first `{`.
  private func closingLine(_ lines: [String], from start: Int) -> Int? {
    var depth = 0
    var opened = false
    for index in start..<lines.count {
      for character in lines[index] {
        if character == "{" {
          depth += 1
          opened = true
        } else if character == "}" {
          depth -= 1
          if opened, depth == 0 { return index }
        }
      }
    }
    return nil
  }

  /// A `.nomiCard` chained onto the closing brace (same line, after the `}`),
  /// or onto the modifier lines that follow it.
  private func cardChained(_ lines: [String], closingLine: Int) -> Int? {
    let afterBrace = lines[closingLine].components(separatedBy: "}").last ?? ""
    if afterBrace.contains(".nomiCard(") { return closingLine }
    var index = closingLine + 1
    while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(".") {
      if lines[index].contains(".nomiCard(") { return index }
      index += 1
    }
    return nil
  }

  /// The nearest `{` above `start` whose block is still open at `start`. Scans
  /// from the line before `start`, so the row's own trailing `{` is not found.
  private func enclosingOpener(_ lines: [String], before start: Int) -> Int? {
    var depth = 0
    var index = start - 1
    while index >= 0 {
      for character in lines[index].reversed() {
        if character == "}" {
          depth += 1
        } else if character == "{" {
          if depth == 0 { return index }
          depth -= 1
        }
      }
      index -= 1
    }
    return nil
  }
}
