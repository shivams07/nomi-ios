#if DEBUG && (targetEnvironment(simulator) || os(macOS))
import Foundation
import NomiCore

/// Debug simulator only. `NOMI_START_ROUTE=<name>` opens one screen at launch,
/// so `xcrun simctl launch` followed by `xcrun simctl io <udid> screenshot`
/// captures any screen with no taps. Pairs with `NOMI_DEMO_DATA=1`, which also
/// completes first run in memory (see `AppServices.launchPreferences`).
///
/// **Read in a Debug simulator build only.** The readers below are guarded by
/// `DEBUG && targetEnvironment(simulator)`, and every call site in
/// `NomiAppScene.swift` and `RootView.swift` sits inside that guard, so a Release
/// build contains no reader and no `NOMI_START_ROUTE` string. This file itself
/// is also compiled on the host, so the parser can be tested there.
///
/// **Unknown values are ignored.** An empty value, or any name not in the list,
/// starts the app on its normal screen. `launch` logs an unknown value once.
enum DevLaunchRoute: String, CaseIterable, Equatable, Sendable {
  case home
  case activity
  case insights
  case plan
  case settings
  /// Settings > About. Pushed by value on Home's stack (see `DevLaunchScreen`).
  case about
  /// About > Open-source licences. Pushed by value after About.
  case licences
  case budgets
  case accounts
  case connectMail
  /// First run: Welcome. Leaves the first-run flag open.
  case welcome
  /// First run: Bring in your data. Steps on from Welcome.
  case bringData
  /// The Import screen, raw value `import`.
  case importStatement = "import"
  /// The Add transaction sheet.
  case add

  /// The variable this reads.
  static let environmentKey = "NOMI_START_ROUTE"

  /// The route for one value. Exact and case-sensitive. Nil for `nil`, for an
  /// empty value and for any name the list does not have.
  static func parse(_ value: String?) -> DevLaunchRoute? {
    guard let value else { return nil }
    return DevLaunchRoute(rawValue: value)
  }

  /// The route named in a launch environment, whatever the build.
  static func parse(environment: [String: String]) -> DevLaunchRoute? {
    parse(environment[environmentKey])
  }

  /// The route named in `environment`, honoured only in a Debug simulator build.
  /// Everywhere else the answer is nil, whatever the environment holds.
  static func fromLaunchEnvironment(_ environment: [String: String]) -> DevLaunchRoute? {
    #if DEBUG && targetEnvironment(simulator)
      return parse(environment: environment)
    #else
      _ = environment
      return nil
    #endif
  }

  /// The route this launch asked for, read once from the process environment.
  /// An unknown value is logged once here and then ignored.
  static let launch: DevLaunchRoute? = {
    #if DEBUG && targetEnvironment(simulator)
      let environment = ProcessInfo.processInfo.environment
      let route = fromLaunchEnvironment(environment)
      if route == nil, let raw = environment[environmentKey], !raw.isEmpty {
        NomiLog.store.notice("NOMI_START_ROUTE ignored: \(raw, privacy: .public) is not a route")
      }
      return route
    #else
      return nil
    #endif
  }()

  /// The first-run screen this route opens, for the two onboarding routes. Every
  /// other route is a shell screen, and `nil` here.
  var onboardingStep: OnboardingStep? {
    switch self {
    case .welcome:
      return .welcome
    case .bringData:
      return .bringData
    default:
      return nil
    }
  }

  /// Whether `NOMI_DEMO_DATA=1` completes first run for a launch with `route`.
  /// It does, unless the route opens a first-run screen, which needs first run
  /// still open. With no route, the demo completes it.
  static func demoCompletesFirstRun(for route: DevLaunchRoute?) -> Bool {
    route?.onboardingStep == nil
  }

  /// What a launch does with its route, given the first-run flag's state. The
  /// decision is pinned here, for all three flag states and with or without demo
  /// data.
  ///
  /// - A shell route opens in every state. With no first run done, it waits for the
  ///   shell, which appears when first run completes. With demo data the flag is
  ///   set in memory first, so the shell appears at once.
  /// - Welcome and Bring in your data open their step while first run is open. A
  ///   recorded true flag means first run is done, so they do nothing.
  /// - An absent flag and a recorded false are the same first run. `UserDefaults`
  ///   answers false for both, and the gate cannot tell them apart.
  ///
  /// `demo` does not change either answer. The demo overlay sets the flag only for
  /// a shell route (see `demoCompletesFirstRun`), so an onboarding route still
  /// sees the stored flag.
  static func stage(for route: DevLaunchRoute?, flag: FirstRunFlag, demo: Bool) -> DevLaunchStage {
    _ = demo
    guard let route else { return .none }
    if let step = route.onboardingStep {
      return flag == .recordedTrue ? .none : .onboardingStep(step)
    }
    return .shellRoute(route)
  }
}

/// The first-run flag as a launch sees it: never written, written false, or
/// written true. `UserDefaults` cannot tell the first two apart, which is why the
/// decision is pinned for each.
enum FirstRunFlag: CaseIterable, Equatable, Sendable {
  case absent
  case recordedFalse
  case recordedTrue
}

/// What a launch does with its route. See `DevLaunchRoute.stage`.
enum DevLaunchStage: Equatable, Sendable {
  case none
  case onboardingStep(OnboardingStep)
  case shellRoute(DevLaunchRoute)
}

/// A pushed screen with no `HomeRoute` case. About and Licences are inline links
/// in Settings, so the launch route pushes them by value on Home's stack. Back
/// then returns through Settings as it does after a tap.
enum DevLaunchScreen: Hashable, Sendable {
  case about
  case licences
}
#endif
