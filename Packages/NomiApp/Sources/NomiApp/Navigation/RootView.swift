
import NomiCore
import NomiUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The navigation graph. Four tabs and the centre `+` (`RootTab`, `TabBarLayout`;
/// I-15): Home, Activity, `+`, Insights, Plan.
///
/// **Not a `TabView`, deliberately.** `NomiTabBar` is the floating glass capsule the
/// artboards draw, placed 26 pt above the bottom edge with the `+` in the middle. A
/// `TabView` draws its own opaque bar and pins content above it. A `ZStack` over an
/// explicit selection puts the bar over the content, which is the arrangement the
/// artboards show.
///
/// **Tabs are kept alive once visited (Y4).** Each tab is built the first time it is
/// selected, then stays in the ZStack. A switch only changes its opacity and hit
/// testing, so the chip, the scroll position and any pushed screen survive a trip to
/// another tab.
///
/// One `NavigationStack` per tab, each bound to its own `NavigationPath`. Settings,
/// Budgets, Subscriptions, Accounts, Import and Connect mail are pushed onto Home's
/// stack, and the bar is hidden while any of them is open (`TabBarVisibility`).
///
/// **The bottom reserve (D4, Andrews).** A tab root's main scroll view adds
/// `\.nomiTabBarReserve` as bottom content margin, so its last row clears the bar. This
/// view publishes the reserve from one place; it never pads the tab's whole
/// destination, which would pad the chip rows too.
struct RootView: View {
  @ObservedObject var environment: AppEnvironment
  /// Observed so the Plan tab follows `isRequestingPermission` while the OS prompt is up.
  @ObservedObject private var notificationSettings: NotificationSettingsStore
  @State private var selection: RootTab = .home
  /// Tabs that have been selected at least once. A tab is built when it first
  /// appears here and is not torn down after (Y4).
  @State private var visited: Set<RootTab> = [.home]
  @State private var homePath = NavigationPath()
  @State private var activityPath = NavigationPath()
  @State private var insightsPath = NavigationPath()
  @State private var planPath = NavigationPath()
  @State private var isPresentingEntry = false
  @State private var isReviewing = false
  /// The bar's height, from `NomiTabBar`'s `onHeightChange`. The bar is a fixed 68 pt,
  /// so this starts at that value and avoids a first-frame jump in the reserve.
  @State private var tabBarHeight: CGFloat = NomiTabBarMetrics.barHeight
  /// What the last "show Activity" request asked for, and a counter that changes on each
  /// request, so Activity is rebuilt and its chip is read again (`.id`).
  @State private var activityRequest: ActivityRequest = .all
  @State private var activityRequestID = 0
  @State private var backfillProgress: BackfillProgress?
  @State private var backfillUnfinished = false
  @State private var presentedTransaction: PresentedTransaction?
  /// True between the system's keyboard-will-show and keyboard-will-hide, so the
  /// bar can step aside and leave the Activity search field clear (D2).
  @State private var keyboardVisible = false

  /// The live account list, passed to Settings and on to `RulesScreen`, so the rule
  /// editor's Account picker has something to show. Sorted like `AccountPickerSheet`
  /// and includes archived rows, so a rule scoped to an archived account still names
  /// it. Read from the app container attached in `NomiAppScene`, never from a preview
  /// container, so this `@Query` cannot reach a schema without `Account`.
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  init(environment: AppEnvironment) {
    _environment = ObservedObject(wrappedValue: environment)
    _notificationSettings = ObservedObject(wrappedValue: environment.notificationSettings)
  }

  /// Shared by the Home Upcoming card, Settings' Subscriptions route and the Plan tab,
  /// so each agrees on the same cache-backed construction.
  private var recurringStore: SwiftDataRecurringStore {
    SwiftDataRecurringStore(
      context: environment.container.mainContext, cache: environment.cache,
      dismissals: environment.preferences)
  }

  /// `LedgerScreen`'s own row-tap sheet and the Home recent-row sheet below both edit
  /// through the same coordinator, so one call site serves both.
  private var transactionEditor: SwiftDataTransactionEditor {
    SwiftDataTransactionEditor(context: environment.container.mainContext, coordinator: environment.coordinator)
  }

  /// The Needs-you card's two taps (G1). Each one hands its request to the Activity
  /// writer through `NeedsYouRoute`, so the pairing is the one `NeedsYouRouteTests` pins.
  private var needsYouTaps: NeedsYouRoute.Taps {
    NeedsYouRoute.taps { request in
      NeedsYouRoute.apply(request, request: { showActivity($0) })
    }
  }

  /// The refresh token for each cache-backed route, all from one generation (G1, G4).
  private var tokens: RouteTokens {
    RouteTokens(generation: environment.insightsGeneration)
  }

  /// Whether the bar is on screen right now: only on a tab root.
  private var isTabBarShown: Bool {
    TabBarVisibility.isVisible(pathCount: pathCount(for: selection))
  }

  /// The bar is drawn only on a tab root and only while the keyboard is down. The
  /// reserve still follows `isTabBarShown`, so a list does not jump when the keyboard
  /// closes.
  private var isTabBarDrawn: Bool {
    TabBarVisibility.isVisible(pathCount: pathCount(for: selection), keyboardVisible: keyboardVisible)
  }

  var body: some View {
    NomiTabShell {
      GeometryReader { shell in
        ZStack(alignment: .bottom) {
          tabs
            .safeAreaInset(edge: .top) {
              if BackfillBannerVisibility.shouldShow(progress: backfillProgress, unfinished: backfillUnfinished) {
                BackfillBanner(progress: backfillProgress ?? BackfillProgress(scanned: 0, total: 0, created: 0))
                  .padding(.horizontal, NomiSpacing.screenGutter)
                  .padding(.top, NomiSpacing.xs)
              }
            }
          if isTabBarDrawn {
            tabBar
          }
        }
        // Every tab root reads this. A pushed screen sees 0, because the bar is hidden there.
        .environment(
          \.nomiTabBarReserve,
          isTabBarShown
            ? NomiTabBarReserve.margin(barHeight: tabBarHeight, safeAreaBottom: shell.safeAreaInsets.bottom)
            : 0
        )
      }
    }
    .modifier(ShellEnvironment(actions: shellActions))
    #if os(iOS)
    // The keyboard takes the bar away while it is up: the bar otherwise rides up over a
    // focused search field (D2). `tabBar` also ignores the keyboard.
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
      keyboardVisible = true
    }
    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
      keyboardVisible = false
    }
    #endif
    .task {
      backfillUnfinished = await environment.mail.backfillIsUnfinished
      for await tick in environment.mailConnectionService.backfillProgress {
        backfillProgress = tick
        backfillUnfinished = await environment.mail.backfillIsUnfinished
      }
    }
    .sheet(isPresented: $isPresentingEntry) {
      // The "Add" bottom sheet. `EntryView` reads categories through `@Query`, so the
      // container has to reach it. A sheet is a new presentation context and does not
      // inherit the root's `.modelContainer`.
      ShellSheet(actions: shellActions) {
        EntryView(
          transactionStore: environment.transactionStore,
          categoryStore: environment.categoryStore,
          onSaved: { isPresentingEntry = false }
        )
        .modelContainer(environment.container)
      }
    }
    .sheet(item: $presentedTransaction) { presented in
      // Home's recent-row tap and the Activity row tap both open the same detail. A new
      // presentation context needs its own `.modelContainer`.
      ShellSheet(actions: shellActions) {
        TransactionDetailScreen(
          transactionID: presented.id,
          transactionStore: environment.transactionStore,
          editor: transactionEditor,
          categoryStore: environment.categoryStore,
          accountStore: environment.accountStore,
          suggester: environment.categorySuggester
        )
        .modelContainer(environment.container)
      }
    }
    #if os(iOS)
    .fullScreenCover(isPresented: $isReviewing) {
      reviewCover
    }
    #else
    .sheet(isPresented: $isReviewing) {
      reviewCover
    }
    #endif
  }

  // MARK: - Shell actions

  /// The actions every screen under the shell can reach (I-15). Sheets and covers get
  /// the same set through `ShellSheet`.
  private var shellActions: ShellActions {
    ShellActions(
      addTransaction: NomiAddTransactionAction { isPresentingEntry = true },
      showLedger: NomiShowLedgerAction { showActivity($0) },
      openReview: NomiShellAction { isReviewing = true },
      showPlan: NomiShellAction { show(.plan) },
      openImport: NomiShellAction { openImport() },
      ruleStore: environment.ruleStore,
      insightsStore: environment.insightsStore
    )
  }

  /// The Review queue, presented full screen. It has its own `.modelContainer`, like
  /// every presentation.
  private var reviewCover: some View {
    ShellSheet(actions: shellActions) {
      ReviewQueueScreen(
        transactionStore: environment.transactionStore,
        insightsStore: environment.insightsStore,
        categoryStore: environment.categoryStore,
        ruleStore: environment.ruleStore,
        accountStore: environment.accountStore,
        editor: transactionEditor,
        suggester: environment.categorySuggester,
        onClose: { isReviewing = false }
      )
      .modelContainer(environment.container)
    }
  }

  // MARK: - Tabs

  /// Each visited tab, built once and then kept. Only the selected one is visible and
  /// hit-testable.
  private var tabs: some View {
    ZStack {
      ForEach(RootTab.allCases) { tab in
        if visited.contains(tab) {
          tabRoot(tab)
            .opacity(tab == selection ? 1 : 0)
            .allowsHitTesting(tab == selection)
            .accessibilityHidden(tab != selection)
        }
      }
    }
  }

  @ViewBuilder
  private func tabRoot(_ tab: RootTab) -> some View {
    switch tab {
    case .home: homeStack
    case .activity: activityStack
    case .insights: insightsStack
    case .plan: planStack
    }
  }

  // MARK: - Tab bar

  private var tabBar: some View {
    let slots = barSlots
    return NomiTabBar(
      leading: slots.leading,
      trailing: slots.trailing,
      selectedID: selection.id,
      onSelect: { id in
        if let tab = RootTab(rawValue: id) {
          select(tab)
        }
      },
      onAdd: { isPresentingEntry = true },
      onHeightChange: { tabBarHeight = $0 }
    )
    .frame(maxWidth: .infinity)
    .padding(.bottom, NomiTabBarMetrics.bottomOffset)
    .ignoresSafeArea(.container, edges: .bottom)
    // Keep the bar fixed when the keyboard rises, so it never slides up over a field.
    .ignoresSafeArea(.keyboard, edges: .bottom)
  }

  /// The two halves of the bar, read from `TabBarLayout.items` so the order is written
  /// in one place. `NomiTabBar` puts the `+` between them.
  private var barSlots: (leading: [NomiTabBarItem], trailing: [NomiTabBarItem]) {
    var leading: [NomiTabBarItem] = []
    var trailing: [NomiTabBarItem] = []
    var passedAdd = false
    for item in TabBarLayout.items {
      switch item {
      case .add:
        passedAdd = true
      case .tab(let tab):
        let slot = NomiTabBarItem(id: tab.id, title: tab.title, symbolName: tab.symbolName)
        if passedAdd {
          trailing.append(slot)
        } else {
          leading.append(slot)
        }
      }
    }
    return (leading, trailing)
  }

  /// Selects `tab` from a tap. Selecting the tab that is already showing pops its stack
  /// to the root, the usual iOS behaviour for a tab bar.
  private func select(_ tab: RootTab) {
    if tab == selection {
      popToRoot(tab)
    }
    show(tab)
  }

  /// Makes `tab` the selected tab and records that it has been visited, so it is built
  /// once and then kept (Y4). Every route to a tab goes through here.
  private func show(_ tab: RootTab) {
    visited.insert(tab)
    selection = tab
  }

  /// Opens the Activity tab on `request` (`ShowLedgerRoute`). Clears Home's stack, so no
  /// pushed screen is left over it. The Activity stack is left as it was, but rebuilt
  /// with the new chip through `activityRequestID`.
  private func showActivity(_ request: ActivityRequest) {
    activityRequest = request
    activityRequestID += 1
    let outcome = ShowLedgerRoute.outcome()
    if outcome.clearsHomeStack {
      homePath = NavigationPath()
    }
    show(outcome.selection)
  }

  /// Dismisses any sheet or cover, selects Home and pushes the Import screen.
  private func openImport() {
    isPresentingEntry = false
    presentedTransaction = nil
    isReviewing = false
    show(.home)
    homePath.append(HomeRoute.importStatement)
  }

  private func popToRoot(_ tab: RootTab) {
    switch tab {
    case .home: homePath = NavigationPath()
    case .activity: activityPath = NavigationPath()
    case .insights: insightsPath = NavigationPath()
    case .plan: planPath = NavigationPath()
    }
  }

  private func pathCount(for tab: RootTab) -> Int {
    switch tab {
    case .home: return homePath.count
    case .activity: return activityPath.count
    case .insights: return insightsPath.count
    case .plan: return planPath.count
    }
  }

  // MARK: - Tab roots

  private var homeStack: some View {
    NavigationStack(path: $homePath) {
      DashboardView(
        insightsStore: environment.insightsStore,
        mailConnectionService: environment.mailConnectionService,
        // Built here rather than held on `AppEnvironment`, per U17b's own spec:
        // `SwiftDataInsightsStore` and `SwiftDataRecurringStore` already share
        // `environment.cache`, so constructing this here costs nothing beyond the call.
        recurringStore: recurringStore,
        // Stored and never read by the screen — see `DashboardView`'s note. It is what
        // makes SwiftUI re-invoke `body` after a write, and it is only doing that job
        // because it *changes*: passing a literal here would compile and fix nothing.
        refreshToken: tokens.dashboard,
        onOpenReviewQueue: needsYouTaps.reviewQueue,
        // G1. The Needs-you card calls this when its only count is uncategorized rows.
        onOpenUncategorized: needsYouTaps.uncategorized,
        onSelectTransaction: { id in presentedTransaction = PresentedTransaction(id: id) }
      )
      // The back button on a pushed screen reads this title, so Home keeps it even though
      // its own nav bar is hidden by the hero.
      .navigationTitle("Home")
      .navigationDestination(for: DashboardRoute.self) { route in
        switch route {
        // G4. Both routes take the cache generation, so a pushed screen re-reads after a
        // sync or a Siri write.
        case .budgets:
          BudgetsScreen(
            budgetStore: environment.budgetStore,
            insightsStore: environment.insightsStore,
            refreshToken: tokens.budgets
          )
        case .subscriptions:
          SubscriptionsScreen(recurringStore: recurringStore, refreshToken: tokens.subscriptions)
        }
      }
      // The gear (Settings), the mail banner or Connect mail button, Settings' Accounts
      // and Import rows, and the first scan.
      .navigationDestination(for: HomeRoute.self) { route in
        switch route {
        case .settings:
          SettingsScreen(
            mailConnectionService: environment.mailConnectionService,
            fileImportService: environment.fileImportService,
            categoryStore: environment.categoryStore,
            ruleStore: environment.ruleStore,
            notificationSettings: environment.notificationSettings.binding,
            storageMode: environment.storageMode,
            accounts: accounts,
            // The Budgets row under Organize needs both stores; without them SettingsScreen
            // shows no row.
            budgetStore: environment.budgetStore,
            insightsStore: environment.insightsStore,
            refreshToken: tokens.settings
          )
        case .connectMail:
          ConnectMailScreen(
            mailConnectionService: environment.mailConnectionService,
            onBackfillStart: { homePath.append(HomeRoute.backfill) }
          )
        case .accounts:
          AccountsScreen(
            accountStore: environment.accountStore,
            insightsStore: environment.insightsStore,
            refreshToken: tokens.plan
          )
        case .importStatement:
          ImportEntryView(fileImportService: environment.fileImportService)
        case .backfill:
          BackfillScreen(
            mailConnectionService: environment.mailConnectionService,
            months: 6,
            onFinish: { homePath.removeLast() }
          )
        }
      }
    }
  }

  private var activityStack: some View {
    NavigationStack(path: $activityPath) {
      // `LedgerScreen` sets its own title. It reads `initialChip` once, when it is built,
      // so `.id(activityRequestID)` rebuilds it for each request.
      LedgerScreen(
        transactionStore: environment.transactionStore,
        categoryStore: environment.categoryStore,
        accountStore: environment.accountStore,
        editor: transactionEditor,
        initialChip: ActivityRoute.chip(for: activityRequest),
        suggester: environment.categorySuggester,
        // Whole-ledger search (D2). Without it the search box filters only the 90-day window.
        transactionSearch: environment.transactionSearch
      )
      .id(activityRequestID)
      .environment(\.nomiActivityRequest, activityRequest)
    }
  }

  private var insightsStack: some View {
    NavigationStack(path: $insightsPath) {
      // `ReportsScreen` sets its own "Insights" title.
      ReportsScreen(
        insightsStore: environment.insightsStore,
        refreshToken: tokens.reports
      )
    }
  }

  private var planStack: some View {
    NavigationStack(path: $planPath) {
      PlanScreen(
        budgetStore: environment.budgetStore,
        insightsStore: environment.insightsStore,
        recurringStore: recurringStore,
        notificationSettings: environment.notificationSettings.binding,
        isRequestingNotificationPermission: notificationSettings.isRequestingPermission,
        refreshToken: tokens.plan
      )
    }
  }
}

/// The shell actions, bundled so the shell and each sheet get the same set.
private struct ShellActions {
  let addTransaction: NomiAddTransactionAction
  let showLedger: NomiShowLedgerAction
  let openReview: NomiShellAction
  let showPlan: NomiShellAction
  let openImport: NomiShellAction
  let ruleStore: any RuleStore
  let insightsStore: any InsightsStore
}

/// Puts the shell actions into the environment of a sheet or cover's content, so a
/// screen presented from the shell reaches the same actions the shell does.
private struct ShellSheet<Content: View>: View {
  let actions: ShellActions
  let content: Content

  init(actions: ShellActions, @ViewBuilder content: () -> Content) {
    self.actions = actions
    self.content = content()
  }

  var body: some View {
    content.modifier(ShellEnvironment(actions: actions))
  }
}

/// The shell actions as environment values. Applied to the shell and to each sheet.
private struct ShellEnvironment: ViewModifier {
  let actions: ShellActions

  func body(content: Content) -> some View {
    content
      .environment(\.nomiAddTransaction, actions.addTransaction)
      .environment(\.nomiShowLedger, actions.showLedger)
      .environment(\.nomiOpenReview, actions.openReview)
      .environment(\.nomiShowPlan, actions.showPlan)
      .environment(\.nomiOpenImport, actions.openImport)
      .environment(\.nomiRuleStore, actions.ruleStore)
      .environment(\.nomiInsightsStore, actions.insightsStore)
  }
}

extension TabBarVisibility {
  /// The bar is drawn only on a tab root and only while the keyboard is down
  /// (fid-ledger-search, D2). Defined here rather than beside `isVisible(pathCount:)`
  /// in `RootTab.swift`. Pure, so `TabBarKeyboardVisibilityTests` pins it without a view.
  public static func isVisible(pathCount: Int, keyboardVisible: Bool) -> Bool {
    isVisible(pathCount: pathCount) && !keyboardVisible
  }
}
