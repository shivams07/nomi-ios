#if DEBUG && (targetEnvironment(simulator) || os(macOS))
import Foundation
import XCTest

@testable import NomiApp

/// The Debug-simulator launch routes: `NOMI_START_ROUTE` opens one screen at
/// launch, and `NOMI_DEMO_DATA=1` also completes first run, in memory only.
///
/// The parser is pure, so every value is checked on the host. The readers are
/// simulator-only, and the tests that need them say so.
final class DevLaunchRouteTests: XCTestCase {

  /// The documented values, one per route, in the order the spec lists them.
  private let everyValue: [(value: String, route: DevLaunchRoute)] = [
    ("home", .home),
    ("activity", .activity),
    ("insights", .insights),
    ("plan", .plan),
    ("settings", .settings),
    ("about", .about),
    ("licences", .licences),
    ("budgets", .budgets),
    ("accounts", .accounts),
    ("connectMail", .connectMail),
    ("welcome", .welcome),
    ("bringData", .bringData),
    ("import", .importStatement),
    ("add", .add),
  ]

  // MARK: - Parser

  func testEveryDocumentedValueParsesToItsRoute() {
    for (value, route) in everyValue {
      XCTAssertEqual(DevLaunchRoute.parse(value), route, value)
    }
  }

  func testTheRouteListIsExactlyTheDocumentedValues() {
    XCTAssertEqual(DevLaunchRoute.allCases.count, 14)
    XCTAssertEqual(Set(DevLaunchRoute.allCases.map(\.rawValue)), Set(everyValue.map(\.value)))
  }

  func testAnUnknownValueIsIgnored() {
    for value in ["Home", "SETTINGS", "importStatement", "bring-data", "settings ", "tabs", "0", "1"] {
      XCTAssertNil(DevLaunchRoute.parse(value), value)
    }
  }

  func testAnEmptyOrAbsentValueIsIgnored() {
    XCTAssertNil(DevLaunchRoute.parse(""))
    XCTAssertNil(DevLaunchRoute.parse(nil))
  }

  func testTheEnvironmentParserReadsOnlyNomiStartRoute() {
    XCTAssertEqual(DevLaunchRoute.parse(environment: ["NOMI_START_ROUTE": "plan"]), .plan)
    XCTAssertNil(DevLaunchRoute.parse(environment: ["NOMI_DEMO_DATA": "1"]))
    XCTAssertNil(DevLaunchRoute.parse(environment: [:]))
  }

  /// The reader honours the variable only in a Debug simulator build. On the
  /// host, and in any other build, the answer is `nil` whatever the environment holds.
  func testTheReaderHonoursTheVariableOnlyInASimulatorDebugBuild() {
    let read = DevLaunchRoute.fromLaunchEnvironment(["NOMI_START_ROUTE": "plan"])
    #if targetEnvironment(simulator)
      XCTAssertEqual(read, .plan)
    #else
      XCTAssertNil(read)
    #endif
  }

  // MARK: - Onboarding and first run

  func testOnlyWelcomeAndBringDataAreOnboardingScreens() {
    XCTAssertEqual(DevLaunchRoute.welcome.onboardingStep, .welcome)
    XCTAssertEqual(DevLaunchRoute.bringData.onboardingStep, .bringData)
    for route in DevLaunchRoute.allCases where route != .welcome && route != .bringData {
      XCTAssertNil(route.onboardingStep, route.rawValue)
    }
  }

  func testDemoDataCompletesFirstRunUnlessTheRouteIsAnOnboardingScreen() {
    XCTAssertTrue(DevLaunchRoute.demoCompletesFirstRun(for: nil))
    XCTAssertTrue(DevLaunchRoute.demoCompletesFirstRun(for: .settings))
    XCTAssertFalse(DevLaunchRoute.demoCompletesFirstRun(for: .welcome))
    XCTAssertFalse(DevLaunchRoute.demoCompletesFirstRun(for: .bringData))
  }

  // MARK: - Source pins

  /// Every use of the launch route in the composition root and the shell sits
  /// inside `#if DEBUG && targetEnvironment(simulator)`, so a Release build has
  /// no reader to call. The parser file itself opens with the same guard
  /// (plus the host, so these tests compile there).
  func testEveryLaunchRouteUseIsInsideTheDebugSimulatorGuard() throws {
    let guardLine = "#if DEBUG && targetEnvironment(simulator)"
    for file in ["Composition/NomiAppScene.swift", "Navigation/RootView.swift"] {
      var open: [String] = []
      for line in try source(file).components(separatedBy: "\n") {
        let code = line.trimmingCharacters(in: .whitespaces)
        if code.hasPrefix("#if ") { open.append(code) }
        if code.hasPrefix("#endif") { open.removeLast() }
        if code.contains("DevLaunchRoute") || code.contains("DevLaunchScreen") {
          XCTAssertTrue(open.contains(guardLine), "\(file) uses the launch route outside the guard: \(code)")
        }
      }
    }
  }

  func testTheParserFileOpensWithTheGuard() throws {
    let first = try source("Composition/DevLaunchRoute.swift")
      .components(separatedBy: "\n")
      .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    XCTAssertEqual(first, "#if DEBUG && (targetEnvironment(simulator) || os(macOS))")
  }

  private func source(_ relative: String) throws -> String {
    // This file is Packages/NomiApp/Tests/NomiAppTests/<name>.swift.
    let package = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
    return try String(
      contentsOf: package.appendingPathComponent("Sources/NomiApp/\(relative)"), encoding: .utf8)
  }
}

#if targetEnvironment(simulator)
  /// The demo overlay, which the simulator's launch path builds. The host has no
  /// simulator launch, so these run only where the reader is live.
  @MainActor
  final class DevLaunchPreferencesTests: XCTestCase {

    private func suite() -> UserDefaults {
      UserDefaults(suiteName: "DevLaunchPreferencesTests.\(UUID().uuidString)")!
    }

    func testDemoDataCompletesFirstRunInMemoryOnly() {
      let defaults = suite()
      let prefs = AppServices.launchPreferences(
        persistent: true, defaults: defaults, environment: ["NOMI_DEMO_DATA": "1"])
      XCTAssertTrue(prefs.bool(forKey: PreferenceKey.hasCompletedFirstRun))
      XCTAssertFalse(
        defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun),
        "the real preference store must never see the demo's flag")
    }

    func testDemoDataWithAnOnboardingRouteLeavesFirstRunOpen() {
      let defaults = suite()
      let prefs = AppServices.launchPreferences(
        persistent: true, defaults: defaults,
        environment: ["NOMI_DEMO_DATA": "1", "NOMI_START_ROUTE": "welcome"])
      XCTAssertFalse(prefs.bool(forKey: PreferenceKey.hasCompletedFirstRun))
    }

    func testWithoutDemoDataNoLaunchRouteSetsTheFlag() {
      let defaults = suite()
      let prefs = AppServices.launchPreferences(
        persistent: true, defaults: defaults, environment: ["NOMI_START_ROUTE": "settings"])
      XCTAssertFalse(prefs.bool(forKey: PreferenceKey.hasCompletedFirstRun))
      XCTAssertFalse(defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun))
    }
  }
#endif
#endif
