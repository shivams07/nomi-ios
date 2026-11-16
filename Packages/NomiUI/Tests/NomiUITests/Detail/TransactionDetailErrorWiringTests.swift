import XCTest

/// The detail sheet's error alert must show the rule switch's error, not only its own.
/// A rule write that the store refuses sets `TransactionRuleSwitchModel.errorMessage`; if the
/// screen does not read it, the switch snaps back and the user sees nothing. The alert itself is
/// decided by SwiftUI at runtime and no unit test reaches it, so this is a source-scan gate (as
/// `DestructiveConfirmationTests` is).
final class TransactionDetailErrorWiringTests: XCTestCase {

  private func screenSource() throws -> String {
    // This file is Packages/NomiUI/Tests/NomiUITests/Detail/<name>.swift.
    let detail = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // Detail
      .deletingLastPathComponent()  // NomiUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiUI
      .deletingLastPathComponent()  // Packages
      .appendingPathComponent("NomiUI/Sources/NomiUI/Detail/TransactionDetailScreen.swift")
    return try String(contentsOf: detail, encoding: .utf8)
  }

  func testTheDetailAlertReadsTheRuleSwitchError() throws {
    let source = try screenSource()
    XCTAssertTrue(
      source.contains("ruleSwitch.errorMessage"),
      "TransactionDetailScreen must read the rule switch's error, or a refused rule write is silent")
    XCTAssertTrue(
      source.contains("DetailErrorAlert.message(screen: errorMessage, ruleSwitch: ruleSwitch.errorMessage)"),
      "the alert message must come from DetailErrorAlert, with the screen's error first")
  }

  func testDismissingTheAlertClearsBothErrors() throws {
    let source = try screenSource()
    XCTAssertTrue(
      source.contains("ruleSwitch.clearError()"),
      "dismissing the alert must clear the rule switch's error, or the same error shows again")
  }
}
