import CoreData
import NomiCore
import NomiUI
import SwiftUI

#if canImport(UIKit)
  import UIKit
#endif

#if os(iOS)
  import UserNotifications
#endif

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
  /// The store and how it was opened. Built once, on first access. Reading
  /// `storage.persistent` is what constructs it, so the background gate below
  /// reads it only after protected data is known to be available.
  static let storage = NomiModelContainer.makeWithLocalFallback()

  /// When the store is not persistent, preferences read through to what the
  /// user last saved but nothing written this launch reaches `UserDefaults`
  /// (I-6 Amendment 1, step A4).
  static let shared: AppEnvironment = {
    let preferences: any KeyValueStoring =
      storage.persistent
      ? UserDefaultsKeyValueStore()
      : ReadThroughKeyValueStore(reading: UserDefaultsKeyValueStore())
    return AppEnvironment(
      container: storage.container, storageMode: storage.mode, preferences: preferences)
  }()

  /// Whether a background task may run store work. The closure is the only way
  /// to learn persistence, and it is not called without protected data: that is
  /// what keeps the store from being constructed in a background launch before
  /// first unlock (A4).
  static func mayRunStoreWork(protectedDataAvailable: Bool, storeIsPersistent: () -> Bool) -> Bool {
    guard protectedDataAvailable else { return false }
    return storeIsPersistent()
  }

  /// Whether the device's data protection lets this process read its files.
  /// Before first unlock, a background launch cannot open the store.
  static var protectedDataAvailable: Bool {
    #if canImport(UIKit)
      UIApplication.shared.isProtectedDataAvailable
    #else
      true
    #endif
  }

  /// Touched from `NomiAppScene.init`. The `Void`-typed `static let` is the
  /// idiom for "run this once, on first access, thread-safely" — a `Bool` flag
  /// checked and set would be two statements a future edit can separate.
  ///
  /// A background task that fires without protected data, or on a store that is
  /// not persistent, completes with `success: false` and does no work. It does
  /// not reschedule here: the next `.background` scene phase does (A5).
  static let registerBackgroundTasks: Void = {
    AppSyncCoordinator.registerBackgroundTasks { work in
      Task { @MainActor in
        guard
          AppServices.mayRunStoreWork(
            protectedDataAvailable: AppServices.protectedDataAvailable,
            storeIsPersistent: { AppServices.storage.persistent })
        else {
          work.setCompleted(success: false)
          return
        }
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
    // R10. Without a delegate, iOS hides a budget alert raised while the app is
    // in the foreground. The delegate presents it as a banner.
    #if os(iOS)
      UNUserNotificationCenter.current().delegate = NotificationPresentationDelegate.shared
    #endif
    // Inter ships as package resources in `NomiUI`'s bundle. `UIAppFonts` covers
    // only the *app* bundle, and App/Info.plist does not declare it (U18), so
    // `registerIfNeeded` is what puts these faces on the process font table.
    NomiFont.registerIfNeeded()
    // DEC-08 (L1). Installs the navigation bar appearance (F3, I-4). It names
    // the Inter faces, so it runs after registration.
    NomiNavigationAppearance.configure()
  }

  public var body: some Scene {
    WindowGroup {
      RootContainerView(environment: environment)
        // The one place the container is attached. Every `@Query` in the app —
        // `CategoriesScreen`, `RulesScreen`, `EntryView`, `BudgetsScreen`,
        // `ImportEntryView`, the ledger — reads through it.
        .modelContainer(environment.container)
        // DEC-08: light only, for this restyle. See App/Info.plist.
        .preferredColorScheme(.light)
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // A store that is not persistent (I-6 Amendment 1, A6) never syncs in
        // the foreground either. Its cursor writes would die with the process.
        if AppServices.storage.persistent {
          Task { await environment.sync.didBecomeActive() }
        }
        // U9b. `.CKAccountChanged` is not guaranteed to reach a process that
        // was backgrounded while the user signed in or out, so every
        // foreground re-probes. `refresh()` publishes only on a real change,
        // so the common case — nothing changed — costs one status query and
        // no re-render.
        Task { await environment.storageMonitor.refresh() }
      case .background:
        Task { await environment.sync.didEnterBackground() }
      case .inactive:
        // Not a backgrounding (M10). Control Center, the notification shade and
        // the app switcher all pass through `.inactive` with the app still on
        // screen. Treating it as `.background` submitted background tasks and
        // cancelled the foreground sync every time the user pulled a shade down.
        break
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
    #if canImport(UIKit)
    // SB2 (nomi-ios-statusbar-ruling). The anchor attaches the light-bar overlay
    // window once this view is in a window. The tone is published by
    // `NomiHeroScaffold` while a navy hero is under the status bar, and the
    // overlay is shown only for `.light`. Nothing else in this file sets a
    // status bar style.
    .background(StatusBarOverlayAnchor().frame(width: 0, height: 0).accessibilityHidden(true))
    .onPreferenceChange(NomiStatusBarToneKey.self) { tone in
      MainActor.assumeIsolated {
        StatusBarOverlay.shared.apply(tone)
      }
    }
    #endif
    .task {
      await environment.bootstrap()
    }
    .task {
      await observeRemoteChanges()
    }
    .task {
      // U9b. Probes once, then follows `.CKAccountChanged` for as long as this
      // view is alive. A `.task` rather than a fire-and-forget `Task` so it is
      // cancelled with the view instead of outliving it.
      await environment.storageMonitor.run()
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
  ///
  /// Each notification only *reports* a change; the coordinator coalesces a
  /// burst into one reconcile (M10). The cache is dropped by
  /// `AppSyncCoordinator` once the debounced reconcile has run
  /// (`onRemoteChangeSettled`, set in `AppEnvironment`): the import changed
  /// rows the cache had already answered for, whether or not the reconcile then
  /// collapsed anything.
  private func observeRemoteChanges() async {
    let notifications = NotificationCenter.default.notifications(
      named: .NSPersistentStoreRemoteChange
    )
    for await _ in notifications {
      await environment.sync.remoteChangeObserved()
    }
  }
}
