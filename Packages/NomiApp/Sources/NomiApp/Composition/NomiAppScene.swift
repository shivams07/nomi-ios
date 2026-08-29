import CoreData
import NomiCore
import NomiUI
import SwiftUI

/// Process-wide services.
///
/// A global is the right shape here and only here. `BGTaskScheduler.register`
/// hands its work to a closure the *system* invokes, at a moment no view is on
/// screen and no `@StateObject` is in scope; the handler has to be able to reach
/// the composition root from nothing. Registration also has to happen before the
/// app finishes launching and exactly once — registering the same identifier
/// twice raises an `NSException`, which is a crash, not a warning.
///
/// Both properties are `static let`, so both are lazy and both run once. Nothing
/// else in this package reaches for `AppServices`: every screen is handed its
/// stores by `init`, which is the contract `NomiPreview`'s `Fake*` types define
/// (§2.18).
@MainActor
enum AppServices {
  static let shared = AppEnvironment(container: NomiModelContainer.makeWithLocalFallback())

  /// Touched from `NomiAppScene.init`. The `Void`-typed `static let` is the
  /// idiom for "run this once, on first access, thread-safely" — a `Bool` flag
  /// checked and set would be two statements a future edit can separate.
  static let registerBackgroundTasks: Void = {
    AppSyncCoordinator.registerBackgroundTasks { work in
      Task { @MainActor in
        await AppServices.shared.sync.run(work)
      }
    }
  }()
}

/// The app's root scene. `App/Nomi.swift` is one line: `NomiAppScene()`.
///
/// Everything this scene does that is not "show a view" is here because it has
/// to happen at a specific moment in the launch sequence — background-task
/// registration before launch completes, the seed and the reconcile before the
/// first frame the user can act on, the sync on every foreground.
@MainActor
public struct NomiAppScene: Scene {
  @StateObject private var environment = AppServices.shared
  @Environment(\.scenePhase) private var scenePhase

  public init() {
    // Before the app finishes launching, as `BGTaskScheduler` requires.
    _ = AppServices.registerBackgroundTasks
    // U5 ships Montserrat and Inter as package resources and `Info.plist`
    // declares them under `UIAppFonts` — but `UIAppFonts` only covers fonts in
    // the *app* bundle, and these live in `NomiUI`'s. `registerIfNeeded` is
    // U5's own answer to that; nothing had ever called it.
    NomiFont.registerIfNeeded()
  }

  public var body: some Scene {
    WindowGroup {
      RootContainerView(environment: environment)
        // The one place the container is attached. Every `@Query` in the app —
        // `CategoriesScreen`, `RulesScreen`, `EntryView`, `BudgetsScreen`,
        // `ImportEntryView`, the ledger — reads through it.
        .modelContainer(environment.container)
        .preferredColorScheme(.dark)
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        Task { await environment.sync.didBecomeActive() }
      case .background, .inactive:
        Task { await environment.sync.didEnterBackground() }
      @unknown default:
        break
      }
    }
  }
}

/// Splits onboarding from the main app, and owns the once-per-launch work.
///
/// Separate from `NomiAppScene` because a `Scene` has no `.task` — bootstrap
/// has to hang off a `View`, and putting it on `RootView` would re-run it every
/// time onboarding finished.
struct RootContainerView: View {
  @ObservedObject var environment: AppEnvironment
  @ObservedObject private var firstRun: FirstRunGate

  /// `@MainActor` because it reads `environment.firstRun`, and `AppEnvironment`
  /// is main-actor isolated. Constructed from `NomiAppScene.body`, which is too.
  @MainActor
  init(environment: AppEnvironment) {
    self.environment = environment
    self.firstRun = environment.firstRun
  }

  var body: some View {
    Group {
      switch firstRun.route {
      case .onboarding(let step):
        OnboardingFlow(environment: environment, step: step)
      case .main:
        RootView(environment: environment)
      }
    }
    .task {
      await environment.bootstrap()
    }
    .task {
      await observeRemoteChanges()
    }
  }

  /// R5's reconcile, on the event that causes the corruption it fixes.
  ///
  /// SwiftData does not surface a change notification of its own, but its store
  /// is CoreData underneath and posts `NSPersistentStoreRemoteChange` when
  /// CloudKit merges records in. **Whether it fires is not something this
  /// project can verify** — CI does not run the app and no one here has two
  /// devices — so it is an addition to the launch and foreground reconciles,
  /// never a replacement for them. If it never fires, nothing is lost.
  private func observeRemoteChanges() async {
    let notifications = NotificationCenter.default.notifications(
      named: .NSPersistentStoreRemoteChange
    )
    for await _ in notifications {
      await environment.sync.reconcile()
      environment.cache.invalidate()
    }
  }
}
