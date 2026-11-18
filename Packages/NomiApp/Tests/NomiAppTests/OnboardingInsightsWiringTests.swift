import Foundation
import XCTest

/// S12c: the First scan screen reads `\.nomiInsightsStore` for its account rows, and
/// first run draws it outside `RootView`, so `NomiAppScene` must hand the store to
/// `OnboardingFlow` itself. Without it the rows stay hidden in the real first-run flow,
/// and no unit test would notice, because the screen's body is not reachable from one.
/// A source scan of the onboarding branch, the same shape as `TabRootReserveWiringTests`.
final class OnboardingInsightsWiringTests: XCTestCase {
  func testTheOnboardingBranchHandsItsScreensTheInsightsStore() throws {
    // This file is Packages/NomiApp/Tests/NomiAppTests/<name>.swift.
    let packages = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
      .deletingLastPathComponent()  // Packages
    let url = packages.appendingPathComponent("NomiApp/Sources/NomiApp/Composition/NomiAppScene.swift")
    let text = try String(contentsOf: url, encoding: .utf8)

    let onboarding = try XCTUnwrap(
      text.range(of: "case .onboarding(let step):"),
      "NomiAppScene must still switch on the onboarding route")
    let mainRoute = try XCTUnwrap(
      text.range(of: "case .main:", range: onboarding.upperBound..<text.endIndex),
      "NomiAppScene must still have a main route after onboarding")
    let branch = String(text[onboarding.upperBound..<mainRoute.lowerBound])

    XCTAssertTrue(
      branch.contains("OnboardingFlow(environment: environment, step: step)"),
      "the onboarding branch must still draw OnboardingFlow")
    XCTAssertTrue(
      branch.contains(".environment(\\.nomiInsightsStore, environment.insightsStore)"),
      "the onboarding branch must pass environment.insightsStore as \\.nomiInsightsStore (S12c)")
  }
}
