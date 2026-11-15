import Combine
import Foundation
import NomiCore
import SwiftData

/// Where the app opens. The whole of §2.18(2)'s "nothing decides
/// onboarding-vs-main".
public enum AppRoute: Sendable, Equatable {
  case onboarding(OnboardingStep)
  case main
}

/// The screens of first run, in the order a user passes them. Two routes leave
/// Bring in your data: `connectMail` then `backfill` (mail), or
/// `importStatement` alone (a file).
public enum OnboardingStep: Sendable, Equatable {
  case welcome
  case bringData
  case connectMail
  case importStatement
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

  /// `hasStoredData` is consulted only while the flag is absent. It answers
  /// whether the database already holds rows (see `storeHoldsData(in:)`), so an
  /// install whose data came back without the flag, such as an iCloud restore,
  /// is not sent through onboarding.
  public init(store: any KeyValueStoring, hasStoredData: @MainActor () -> Bool = { false }) {
    self.store = store
    let flagged = store.bool(forKey: PreferenceKey.hasCompletedFirstRun)
    let completed = flagged || hasStoredData()
    if completed && !flagged {
      // Written once, so later launches read the flag and never check the store.
      // The write goes to the store this gate was given: in a non-persistent
      // launch that is the in-memory store.
      store.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    }
    self.route = Self.initialRoute(hasCompletedFirstRun: completed)
  }

  /// Whether the store already holds a transaction or an account. A cheap
  /// existence check: each fetch asks for one row. A failed fetch counts as
  /// data, because sending someone with data back to onboarding is the one wrong
  /// answer here that hurts a user, and onboarding can be skipped anyway.
  public static func storeHoldsData(in context: ModelContext) -> Bool {
    func hasRow<Model: PersistentModel>(_ model: Model.Type) -> Bool {
      var descriptor = FetchDescriptor<Model>()
      descriptor.fetchLimit = 1
      return ((try? context.fetchCount(descriptor)) ?? 1) > 0
    }
    return hasRow(NomiCore.Transaction.self) || hasRow(NomiCore.Account.self)
  }

  /// Pure, and the reason this is a static rather than an instance method: it
  /// is the one line the acceptance criterion is about ("a first run lands on
  /// onboarding and a subsequent run does not") and a test can call it without
  /// constructing anything.
  public static func initialRoute(hasCompletedFirstRun: Bool) -> AppRoute {
    hasCompletedFirstRun ? .main : .onboarding(.welcome)
  }

  /// Welcome's "Get started". Only from Welcome.
  public func start() {
    guard case .onboarding(.welcome) = route else { return }
    route = .onboarding(.bringData)
  }

  /// Bring in your data: "Continue with email". Only from Bring in your data.
  public func chooseMail() {
    guard case .onboarding(.bringData) = route else { return }
    route = .onboarding(.connectMail)
  }

  /// Bring in your data: "Import a bank statement". Only from Bring in your data.
  public func chooseImport() {
    guard case .onboarding(.bringData) = route else { return }
    route = .onboarding(.importStatement)
  }

  /// Bring in your data: "Add by hand". Leaves first run, as Skip does.
  public func chooseManual() {
    completeFirstRun()
  }

  /// The back control on connect mail, on import, and on Bring in your data.
  /// Welcome has no back, and backfill has no way back into setup.
  public func back() {
    switch route {
    case .onboarding(.connectMail), .onboarding(.importStatement):
      route = .onboarding(.bringData)
    case .onboarding(.bringData):
      route = .onboarding(.welcome)
    case .onboarding(.welcome), .onboarding(.backfill), .main:
      return
    }
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
    route = .onboarding(.welcome)
  }
}
