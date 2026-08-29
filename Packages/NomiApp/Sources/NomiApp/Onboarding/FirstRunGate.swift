import Combine
import Foundation

/// Where the app opens. The whole of §2.18(2)'s "nothing decides
/// onboarding-vs-main".
public enum AppRoute: Sendable, Equatable {
  case onboarding(OnboardingStep)
  case main
}

/// The two screens U7 built and nothing ever sequenced.
public enum OnboardingStep: Sendable, Equatable {
  case connectMail
  case backfill
}

/// Owns the persisted first-run flag and the decision that reads it.
///
/// **The flag is set when onboarding is *left*, not when mail connects.** Those
/// are different events and conflating them is the bug this type exists to
/// avoid: a user who skips the mail step, or whose connection fails, has still
/// seen onboarding, and showing it to them again on every launch is worse than
/// never showing it. Equally, connecting mail is not on its own a reason to
/// mark first run done — the backfill screen is part of the first run and the
/// user has not reached the app yet.
///
/// `@MainActor` because the flag is read during view construction; the store
/// underneath is thread-safe either way.
@MainActor
public final class FirstRunGate: ObservableObject {
  private let store: any KeyValueStoring

  /// Published so the root view re-renders when onboarding completes. The
  /// persisted flag is the source of truth; this mirrors it.
  @Published public private(set) var route: AppRoute

  public init(store: any KeyValueStoring) {
    self.store = store
    self.route = Self.initialRoute(hasCompletedFirstRun: store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// Pure, and the reason this is a static rather than an instance method: it
  /// is the one line the acceptance criterion is about ("a first run lands on
  /// onboarding and a subsequent run does not") and a test can call it without
  /// constructing anything.
  public static func initialRoute(hasCompletedFirstRun: Bool) -> AppRoute {
    hasCompletedFirstRun ? .main : .onboarding(.connectMail)
  }

  /// Mail connected during onboarding — advance to the backfill screen.
  ///
  /// A no-op once first run is complete. `ConnectMailScreen` fires
  /// `onBackfillStart` from its state stream every time it observes
  /// `.connected`, including when it is reached later from Settings, and
  /// bouncing a returning user into a full backfill because they re-entered
  /// their password is not what that closure means there.
  public func mailConnected() {
    guard case .onboarding = route else { return }
    route = .onboarding(.backfill)
  }

  /// Leave onboarding, whatever happened in it. Persists first, then routes:
  /// backwards, a crash between the two would show onboarding again.
  public func completeFirstRun() {
    store.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    route = .main
  }

  /// Debug/first-launch-after-reinstall affordance. Not wired to any UI; it
  /// exists so the flag has exactly one writer per direction and neither is a
  /// raw `store.set` scattered through a view.
  public func resetForTesting() {
    store.set(false, forKey: PreferenceKey.hasCompletedFirstRun)
    route = .onboarding(.connectMail)
  }
}
