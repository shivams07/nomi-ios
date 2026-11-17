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

  // MARK: - The three flag states, with and without demo data

  /// A shell route opens in every flag state, with or without demo data. An absent
  /// flag and an explicit false are the same first run; only a true flag is done.
  func testAShellRouteOpensInEveryFlagStateWithOrWithoutDemoData() {
    for route in DevLaunchRoute.allCases where route.onboardingStep == nil {
      for flag in FirstRunFlag.allCases {
        for demo in [false, true] {
          XCTAssertEqual(
            DevLaunchRoute.stage(for: route, flag: flag, demo: demo), .shellRoute(route),
            "\(route.rawValue) flag=\(flag) demo=\(demo)")
        }
      }
    }
  }

  /// Welcome and Bring in your data open their step while first run is open, and
  /// do nothing once it is done. Demo data does not change either answer.
  func testAnOnboardingRouteOpensItsStepUnlessFirstRunIsDone() {
    for route in [DevLaunchRoute.welcome, .bringData] {
      guard let step = route.onboardingStep else {
        return XCTFail("\(route.rawValue) has no onboarding step")
      }
      for demo in [false, true] {
        XCTAssertEqual(DevLaunchRoute.stage(for: route, flag: .absent, demo: demo), .onboardingStep(step))
        XCTAssertEqual(DevLaunchRoute.stage(for: route, flag: .recordedFalse, demo: demo), .onboardingStep(step))
        XCTAssertEqual(DevLaunchRoute.stage(for: route, flag: .recordedTrue, demo: demo), .none)
      }
    }
  }

  func testNoRouteDoesNothingInAnyFlagState() {
    for flag in FirstRunFlag.allCases {
      for demo in [false, true] {
        XCTAssertEqual(DevLaunchRoute.stage(for: nil, flag: flag, demo: demo), .none)
      }
    }
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

  /// The Bring in your data step is asked on first appearance and on every route
  /// change, so a route that reaches Welcome after the first look still steps on.
  /// The view wiring is not reachable from `swift test`, so this pins its source.
  /// The decision itself is pinned by `DevLaunchOnboardingStepTests`.
  func testTheBringDataStepIsAskedOnFirstAppearanceAndOnEveryRouteChange() throws {
    let scene = try source("Composition/NomiAppScene.swift")
    XCTAssertTrue(scene.contains(".onChange(of: firstRun.route)"), "the step is asked on each route change")
    XCTAssertTrue(scene.contains("devOnboardingStep.shouldStepOn(for: firstRun.route)"))
    XCTAssertTrue(
      scene.contains("@State private var devOnboardingStep = DevLaunchOnboardingStep(launch: DevLaunchRoute.launch)"))
    XCTAssertTrue(scene.contains(".task {\n      applyOnboardingLaunchRoute()"), "and on first appearance")
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

/// `NOMI_START_ROUTE=bringData` steps Bring in your data on from Welcome. These
/// drive a real `FirstRunGate`, so the route transitions are the ones the app makes.
@MainActor
final class DevLaunchOnboardingStepTests: XCTestCase {

  /// The step is taken when first run is already at Welcome on first appearance.
  func testBringDataStepsOnWhenFirstRunIsAlreadyAtWelcome() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    var step = DevLaunchOnboardingStep(launch: .bringData)
    XCTAssertTrue(step.shouldStepOn(for: gate.route))
    gate.start()
    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  /// The step is taken when first run reaches Welcome after the first look. Before
  /// that, a shell route is on screen and nothing steps. Then the route changes to
  /// Welcome and the step is taken.
  func testBringDataStepsOnWhenFirstRunSettlesToWelcomeLater() {
    let store = InMemoryKeyValueStore()
    store.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    let gate = FirstRunGate(store: store)
    XCTAssertEqual(gate.route, .main)

    var step = DevLaunchOnboardingStep(launch: .bringData)
    XCTAssertFalse(step.shouldStepOn(for: gate.route), "first run is done: nothing to step on")
    XCTAssertTrue(step.isPending, "the step is still owed when first run later reaches Welcome")

    gate.restartAfterErase()
    XCTAssertEqual(gate.route, .onboarding(.welcome))
    XCTAssertTrue(step.shouldStepOn(for: gate.route))
    gate.start()
    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  /// Once taken, the step is not taken again. A Back from Bring in your data to
  /// Welcome is then not stepped forward.
  func testTheStepIsTakenOnlyOnce() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    var step = DevLaunchOnboardingStep(launch: .bringData)
    XCTAssertTrue(step.shouldStepOn(for: gate.route))
    gate.start()
    gate.back()
    XCTAssertEqual(gate.route, .onboarding(.welcome))
    XCTAssertFalse(step.shouldStepOn(for: gate.route))
    XCTAssertFalse(step.isPending)
  }

  /// Only the Bring in your data route owes the step. Every other launch, and every
  /// other route, leaves the gate alone.
  func testNothingElseStepsOn() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    for launch in DevLaunchRoute.allCases where launch != .bringData {
      var step = DevLaunchOnboardingStep(launch: launch)
      XCTAssertFalse(step.isPending, launch.rawValue)
      XCTAssertFalse(step.shouldStepOn(for: gate.route), launch.rawValue)
    }
    var none = DevLaunchOnboardingStep(launch: nil)
    XCTAssertFalse(none.shouldStepOn(for: gate.route))
  }

  /// Only Welcome is a step-on point. Bring in your data, the mail steps and the
  /// shell do not trigger it.
  func testOnlyWelcomeTriggersTheStep() {
    let routes: [AppRoute] = [
      .main, .onboarding(.bringData), .onboarding(.connectMail),
      .onboarding(.importStatement), .onboarding(.backfill),
    ]
    for route in routes {
      var step = DevLaunchOnboardingStep(launch: .bringData)
      XCTAssertFalse(step.shouldStepOn(for: route), "\(route)")
      XCTAssertTrue(step.isPending, "\(route) must not consume the step")
    }
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

    /// Absent, recorded false and recorded true all open a shell route with demo
    /// data, and the real store is left as it was.
    func testDemoDataOpensAShellRouteInEveryRecordedFlagState() {
      for recorded: Bool? in [nil, false, true] {
        let defaults = suite()
        if let recorded {
          defaults.set(recorded, forKey: PreferenceKey.hasCompletedFirstRun)
        }
        let prefs = AppServices.launchPreferences(
          persistent: true, defaults: defaults,
          environment: ["NOMI_DEMO_DATA": "1", "NOMI_START_ROUTE": "settings"])
        XCTAssertTrue(prefs.bool(forKey: PreferenceKey.hasCompletedFirstRun), "recorded=\(String(describing: recorded))")
        XCTAssertEqual(
          defaults.object(forKey: PreferenceKey.hasCompletedFirstRun) as? Bool, recorded,
          "the real store must not change")
      }
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
