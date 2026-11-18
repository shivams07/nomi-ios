import CoreData
import NomiCore
import NomiIngest
import NomiUI
import SwiftData
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
  /// The one source of persistence and protected-data state (I-6 Amendment 1,
  /// A4 to A6). The store opens the first time something reads it, so a
  /// background launch that is refused before first unlock never opens it.
  static let storeWork = StoreWorkEnvironment(
    open: { NomiModelContainer.makeWithLocalFallback() },
    protectedDataAvailable: { systemProtectedDataAvailable })

  /// The app's environment, built by `make` from `storeWork`. Nothing is wired
  /// here of its own: the preference choice, the container and the storage mode
  /// all come from the factory that a test also calls.
  static let shared: AppEnvironment = make(environment: storeWork)

  /// The composition root for one store source. `shared` is the only production
  /// call, with the real defaults. A test passes fakes and its own suite and gets
  /// the same wiring. When the store is not persistent, preferences read through
  /// to what the user last saved, and nothing written this launch reaches
  /// `UserDefaults` (I-6 Amendment 1, A4).
  static func make(
    environment: StoreWorkEnvironment,
    defaults: UserDefaults = .standard,
    credentials: any MailCredentialStoring = KeychainCredentialStore(),
    mailFetcher: any MailFetching = NWIMAPFetcher(),
    scheduler: any BudgetNotificationScheduling = BudgetNotificationScheduler(),
    accountProbe: any CloudKitAccountProbing = CKAccountProbe()
  ) -> AppEnvironment {
    let opened = environment.storage
    return AppEnvironment(
      container: opened.container, storageMode: opened.mode,
      preferences: launchPreferences(persistent: opened.persistent, defaults: defaults),
      credentials: credentials, mailFetcher: mailFetcher, scheduler: scheduler,
      accountProbe: accountProbe)
  }

  /// The preference store for this launch. A non-persistent launch reads through
  /// to what the user last saved, and every write stays in an overlay, so
  /// nothing this launch writes reaches `UserDefaults` (A4). Internal so a test
  /// can drive it with its own suite.
  static func preferenceStore(
    persistent: Bool, defaults: UserDefaults = .standard
  ) -> any KeyValueStoring {
    if persistent {
      return UserDefaultsKeyValueStore(defaults: defaults)
    }
    return ReadThroughKeyValueStore(reading: UserDefaultsKeyValueStore(defaults: defaults))
  }

  /// The preference store for this launch: `preferenceStore`, except that a Debug
  /// simulator launch with `NOMI_DEMO_DATA=1` completes first run here, in memory.
  /// The demo overlay reads through and writes only to its overlay, so the real
  /// `UserDefaults` never sees the flag. A launch whose `NOMI_START_ROUTE` opens
  /// Welcome or Bring in your data keeps first run open. Every other build is
  /// `preferenceStore`.
  static func launchPreferences(persistent: Bool, defaults: UserDefaults) -> any KeyValueStoring {
    #if DEBUG && targetEnvironment(simulator)
      // Reads the route first, so an unknown NOMI_START_ROUTE is logged at launch,
      // before any screen is built. See `DevLaunchRoute.launch`.
      _ = DevLaunchRoute.launch
      return launchPreferences(
        persistent: persistent, defaults: defaults, environment: ProcessInfo.processInfo.environment)
    #else
      return preferenceStore(persistent: persistent, defaults: defaults)
    #endif
  }

  #if DEBUG && targetEnvironment(simulator)
    /// `launchPreferences` for a given launch environment. Internal so a test can
    /// drive it with its own suite and environment.
    static func launchPreferences(
      persistent: Bool, defaults: UserDefaults, environment: [String: String]
    ) -> any KeyValueStoring {
      guard DemoDataSeeder.isRequested(in: environment) else {
        return preferenceStore(persistent: persistent, defaults: defaults)
      }
      let overlay = ReadThroughKeyValueStore(reading: UserDefaultsKeyValueStore(defaults: defaults))
      if DevLaunchRoute.demoCompletesFirstRun(for: DevLaunchRoute.parse(environment: environment)) {
        overlay.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
      }
      return overlay
    }
  #endif

  /// Whether the device's data protection lets this process read its files.
  /// Before first unlock, a background launch cannot open the store.
  static var systemProtectedDataAvailable: Bool {
    #if canImport(UIKit)
      UIApplication.shared.isProtectedDataAvailable
    #else
      true
    #endif
  }

  /// One background task, from the handler the system calls. Without protected
  /// data it completes `success: false` and does not consult the store, so the
  /// store is not constructed in a background launch before first unlock. A
  /// non-persistent store completes the same way. Neither reschedules here; the
  /// next `.background` scene phase does (A5).
  static func runBackground(
    _ work: BackgroundWork,
    storeWork: StoreWorkEnvironment,
    perform: (BackgroundWork) async -> Void
  ) async {
    guard storeWork.mayRunStoreWork() else {
      work.setCompleted(success: false)
      return
    }
    await perform(work)
  }

  /// The foreground sync on `.active`. A non-persistent store does not sync in the
  /// foreground either: its cursor writes would die with the process (A6).
  static func runForegroundSync(_ storeWork: StoreWorkEnvironment, didBecomeActive: () -> Void) {
    guard storeWork.isStorePersistent else { return }
    didBecomeActive()
  }

  /// Touched from `NomiAppScene.init`. The `Void`-typed `static let` is the
  /// idiom for "run this once, on first access, thread-safely" — a `Bool` flag
  /// checked and set would be two statements a future edit can separate.
  static let registerBackgroundTasks: Void = {
    AppSyncCoordinator.registerBackgroundTasks { work in
      Task { @MainActor in
        await AppServices.runBackground(
          work,
          storeWork: AppServices.storeWork,
          perform: { work in await AppServices.shared.sync.run(work) })
      }
    }
  }()
}

/// The one source of persistence and protected-data state for store work (I-6
/// Amendment 1, A4 to A6). The foreground sync, the preference choice in
/// `AppServices.make` and the background handler all read it, and nothing else
/// decides whether store work may run.
///
/// Production builds one, from the real opening path. A test builds one the same
/// way, with the opening path pointed at a file it made, so the gates run against
/// the real classifier and the real in-memory fallback.
///
/// The store opens on the first read of `storage`, and only once. Protected data
/// is read each time it is asked for, never cached.
@MainActor
final class StoreWorkEnvironment {
  typealias OpenedStore = (container: ModelContainer, mode: StorageMode, persistent: Bool)

  private let open: () -> OpenedStore
  private let protectedDataProbe: () -> Bool
  private var opened: OpenedStore?

  init(open: @escaping () -> OpenedStore, protectedDataAvailable: @escaping () -> Bool) {
    self.open = open
    self.protectedDataProbe = protectedDataAvailable
  }

  /// The store and how it was opened. The first read opens it; later reads return
  /// the same value.
  var storage: OpenedStore {
    if let opened { return opened }
    let value = open()
    opened = value
    return value
  }

  /// Whether this process's store writes to disk. Reading it opens the store.
  var isStorePersistent: Bool { storage.persistent }

  /// Whether the device lets this process read its files now.
  var isProtectedDataAvailable: Bool { protectedDataProbe() }

  /// Whether background store work may run. Protected data is checked first, so
  /// without it the store is not opened (c4).
  func mayRunStoreWork() -> Bool {
    guard isProtectedDataAvailable else { return false }
    return isStorePersistent
  }
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
        // `CategoriesScreen`, `RulesScreen`, `EntryView`, `PlanScreen`,
        // `ImportEntryView`, the ledger — reads through it.
        .modelContainer(environment.container)
        // DEC-08: light only, for this restyle. See App/Info.plist.
        .preferredColorScheme(.light)
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // A store that is not persistent never syncs in the foreground (A6).
        AppServices.runForegroundSync(
          AppServices.storeWork,
          didBecomeActive: { Task { await environment.sync.didBecomeActive() } })
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
  #if DEBUG && targetEnvironment(simulator)
    /// The launch's Bring in your data step, taken at most once. See
    /// `applyOnboardingLaunchRoute`.
    @State private var devOnboardingStep = DevLaunchOnboardingStep(launch: DevLaunchRoute.launch)
  #endif

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
    #if DEBUG && targetEnvironment(simulator)
    .task {
      applyOnboardingLaunchRoute()
    }
    // First run can reach Welcome after this view first appears, so the step is
    // asked again on every route change. It answers once per launch.
    .onChange(of: firstRun.route) { _, _ in
      applyOnboardingLaunchRoute()
    }
    #endif
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

  #if DEBUG && targetEnvironment(simulator)
    /// `NOMI_START_ROUTE=bringData` opens Bring in your data. From Welcome, that is
    /// one step on. It is asked on first appearance and on every route change, so
    /// it takes effect whenever first run reaches Welcome. The step itself is
    /// `DevLaunchOnboardingStep`, which answers once. Welcome needs nothing, and
    /// the shell routes are applied by `RootView` once it appears.
    @MainActor
    private func applyOnboardingLaunchRoute() {
      if devOnboardingStep.shouldStepOn(for: firstRun.route) {
        firstRun.start()
      }
    }
  #endif

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
