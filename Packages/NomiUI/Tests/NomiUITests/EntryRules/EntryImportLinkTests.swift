import XCTest

@testable import NomiUI

/// The S5 follow-up: "Import a bank statement instead" sits under Save and calls
/// the shell's import action (`nomiOpenImport`, F3b). A spy stands in for the
/// shell, so the test needs no view hierarchy.
@MainActor
final class EntryImportLinkTests: XCTestCase {

  /// Counts the calls the shell's import action receives.
  @MainActor
  private final class ImportSpy {
    var calls = 0
  }

  func testTappingTheLinkCallsTheImportActionOnce() {
    let spy = ImportSpy()
    let action = NomiShellAction { spy.calls += 1 }
    EntryImportLink.activate(action)
    XCTAssertEqual(spy.calls, 1)
  }

  func testTheLinkWithNoShellDoesNothing() {
    // A sheet with no shell (a preview) draws no link. A call with nil must not crash.
    EntryImportLink.activate(nil)
  }

  func testTheLinkTitleIsTheArtboardCopy() {
    XCTAssertEqual(EntryImportLink.title, "Import a bank statement instead")
  }

  /// Source pins: the link is drawn below Save, it reads the shell action from
  /// the environment, and it is hidden when no shell provides one.
  func testTheLinkSitsBelowSaveAndReadsTheShellAction() throws {
    let text = try entryView()
    let save = try XCTUnwrap(text.range(of: ".disabled(!model.canSave)"))
    let link = try XCTUnwrap(text.range(of: "EntryImportLink.activate(openImport)"))
    XCTAssertLessThan(save.upperBound, link.lowerBound, "the link is drawn below Save")
    XCTAssertTrue(text.contains("@Environment(\\.nomiOpenImport) private var openImport"))
    XCTAssertTrue(text.contains("if let openImport {"), "no shell, no link")
  }

  private func entryView() throws -> String {
    // This file is Packages/NomiUI/Tests/NomiUITests/EntryRules/<name>.swift.
    let package = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // EntryRules
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
    return try String(
      contentsOf: package.appendingPathComponent("Sources/NomiUI/Entry/EntryView.swift"),
      encoding: .utf8)
  }
}
