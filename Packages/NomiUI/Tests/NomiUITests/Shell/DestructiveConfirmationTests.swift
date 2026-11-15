import XCTest

/// Every destructive confirmation must be an `.alert` with an explicit Cancel.
/// A `.confirmationDialog` inside a sheet can present as a popover that drops its
/// Cancel and ignores taps outside it, which left a user with Remove as the only
/// exit (PR #204, Lim, Pro Max). Source-scan, because the presentation is decided
/// by SwiftUI at runtime and no unit test reaches it.
final class DestructiveConfirmationTests: XCTestCase {

  /// Every Swift source under NomiUI and NomiApp, read from `#filePath`.
  private func swiftSources() throws -> [(path: String, text: String)] {
    // This file is Packages/NomiUI/Tests/NomiUITests/Shell/<name>.swift.
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Shell
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
      .deletingLastPathComponent()  // Packages
    let roots = [
      packages.appendingPathComponent("NomiUI/Sources"),
      packages.appendingPathComponent("NomiApp/Sources"),
    ]
    var result: [(String, String)] = []
    for root in roots {
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
      while let url = enumerator?.nextObject() as? URL {
        guard url.pathExtension == "swift" else { continue }
        let text = try String(contentsOf: url, encoding: .utf8)
        result.append((url.path, text))
      }
    }
    XCTAssertFalse(result.isEmpty, "no Swift sources found under \(roots)")
    return result
  }

  /// The call that starts at `line` and the modifiers that belong to it: every
  /// following line indented deeper than the call, plus the closing `}` lines at
  /// the call's own indentation (for `} message: {`).
  private func block(from lines: [String], at index: Int) -> String {
    let indent = lines[index].prefix { $0 == " " }.count
    var end = index
    var next = index + 1
    while next < lines.count {
      let line = lines[next]
      let trimmed = line.drop { $0 == " " }
      let lineIndent = line.prefix { $0 == " " }.count
      if trimmed.isEmpty { next += 1; continue }
      if lineIndent < indent { break }
      if lineIndent == indent && trimmed.hasPrefix(".") { break }
      if lineIndent == indent && !trimmed.hasPrefix("}") && !trimmed.hasPrefix(")") { break }
      end = next
      next += 1
    }
    return lines[index...end].joined(separator: "\n")
  }

  /// `(path, line, kind, block)` for every `.confirmationDialog(` and `.alert(` call.
  private func presentations() throws -> [(where: String, kind: String, block: String)] {
    var found: [(String, String, String)] = []
    for (path, text) in try swiftSources() {
      let lines = text.components(separatedBy: "\n")
      for (i, line) in lines.enumerated() {
        let trimmed = line.drop { $0 == " " }
        guard trimmed.hasPrefix(".confirmationDialog(") || trimmed.hasPrefix(".alert(") else { continue }
        let kind = trimmed.hasPrefix(".confirmationDialog(") ? "confirmationDialog" : "alert"
        let name = (path as NSString).lastPathComponent
        found.append(("\(name):\(i + 1)", kind, block(from: lines, at: i)))
      }
    }
    return found
  }

  /// A destructive confirmation must be an alert, never a confirmation dialog.
  func testNoDestructiveConfirmationDialog() throws {
    let offenders = try presentations().filter {
      $0.kind == "confirmationDialog" && $0.block.contains("role: .destructive")
    }
    XCTAssertTrue(
      offenders.isEmpty,
      "destructive .confirmationDialog (use .alert so Cancel always shows): \(offenders.map(\.where))"
    )
  }

  /// Every destructive alert and dialog has an explicit Cancel.
  func testEveryDestructiveConfirmationHasACancel() throws {
    let missing = try presentations().filter {
      $0.block.contains("role: .destructive") && !$0.block.contains("role: .cancel")
    }
    XCTAssertTrue(
      missing.isEmpty,
      "destructive confirmation without Button(role: .cancel): \(missing.map(\.where))"
    )
  }

  /// The scan finds the sites it is meant to find. Without this, a broken scan
  /// would pass both tests by seeing nothing.
  func testTheScanSeesTheKnownDestructiveConfirmations() throws {
    let destructive = try presentations().filter { $0.block.contains("role: .destructive") }
    XCTAssertTrue(
      destructive.contains { $0.where.hasPrefix("BudgetEditorSheet.swift") },
      "the Budget editor's Remove confirmation was not found; scan is broken"
    )
    XCTAssertGreaterThanOrEqual(destructive.count, 5)
  }
}
