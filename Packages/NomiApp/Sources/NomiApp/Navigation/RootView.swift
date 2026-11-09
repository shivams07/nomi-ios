import NomiCore
import NomiUI
import SwiftData
import SwiftUI

/// The navigation graph. Five slots: Home, Ledger, the centre `+`, Insights,
/// Accounts (`RootTab`, `TabBarLayout`; SIMP §0).
///
/// **Not a `TabView`, deliberately.** `NomiTabBar` (F3) is the glass capsule the
/// artboards draw, floating 22 pt above the bottom edge with the `+` in the
/// middle. A `TabView` draws its own opaque bar and pins content above it. A
/// `ZStack` over an explicit selection puts the bar over the content, which is
/// the arrangement the artboards show.
///
/// One `NavigationStack` per tab, each bound to its own `NavigationPath`.
/// Settings, Budgets, Subscriptions and Connect mail are pushed onto Home's
/// stack, and the bar is hidden while any of them is open (`TabBarVisibility`).
/// The paths live here rather than inside the stacks, so a pushed screen is still
/// there when its tab is selected again.
struct RootView: View {
  @ObservedObject var environment: AppEnvironment
  @State private var selection: RootTab = .home
  @State private var homePath = NavigationPath()
  @State private var ledgerPath = NavigationPath()
  @State private var insightsPath = NavigationPath()
  @State private var accountsPath = NavigationPath()
  @State private var isPresentingEntry = false
  @State private var tabBarHeight: CGFloat = 0
  @State private var ledgerInitialChip: LedgerChipSelection = .all
  @State private var backfillProgress: BackfillProgress?
  @State private var backfillUnfinished = false
  @State private var presentedTransaction: PresentedTransaction?

  /// The live account list, passed to Settings and on to `RulesScreen`, so the
  /// rule editor's Account picker has something to show. Sorted like
  /// `AccountPickerSheet` and includes archived rows, so a rule scoped to an
  /// archived account still names it. Read from the app container attached in
  /// `NomiAppScene`, never from a preview container, so this `@Query` cannot
  /// reach a schema without `Account`.
  @Query(sort: \NomiCore.Account.displayName) private var accounts: [NomiCore.Account]

  /// Shared by the Home Upcoming card and its `SubscriptionsScreen` destination
  /// below, so both agree on the same cache-backed construction.
  private var recurringStore: SwiftDataRecurringStore {
    SwiftDataRecurringStore(context: environment.container.mainContext, cache: environment.cache)
  }

  /// `LedgerScreen`'s own row-tap sheet and the Home recent-row sheet below
  /// both edit through the same coordinator, so one call site serves both.
  private var transactionEditor: SwiftDataTransactionEditor {
    SwiftDataTransactionEditor(context: environment.container.mainContext, coordinator: environment.coordinator)
  }

  /// Whether the bar is on screen right now: only on a tab root.
  private var isTabBarShown: Bool {
    TabBarVisibility.isVisible(pathCount: pathCount(for: selection))
  }

  var body: some View {
    NomiTabShell {
      ZStack(alignment: .bottom) {
        destination
          .safeAreaInset(edge: .top) {
            if BackfillBannerVisibility.shouldShow(progress: backfillProgress, unfinished: backfillUnfinished) {
              BackfillBanner(progress: backfillProgress ?? BackfillProgress(scanned: 0, total: 0, created: 0))
                .padding(.horizontal, NomiSpacing.screenGutter)
                .padding(.top, NomiSpacing.xs)
            }
          }
          .safeAreaInset(edge: .bottom) {
            // Reserved only while the bar is up. A pushed screen runs to the
            // bottom edge.
            Color.clear.frame(height: isTabBarShown ? TabBarInsetHeight.reserved(barHeight: tabBarHeight) : 0)
          }
        if isTabBarShown {
          tabBar
        }
      }
    }
    // The "+" slot and any "Add transaction" button in the app open this sheet.
    .environment(\.nomiAddTransaction, NomiAddTransactionAction { isPresentingEntry = true })
    // Home "See all" and Import "View in Ledger" (FU-1). Both sit on Home's stack.
    .environment(\.nomiShowLedger, NomiShowLedgerAction { showLedger() })
    .onChange(of: selection) { _, newValue in
      // `LedgerScreen` only reads `initialChip` once, at construction — the
      // instance is torn down the moment `selection` leaves `.ledger`. Reset
      // here so a plain tab tap back in never inherits the review chip
      // `onOpenReviewQueue` set.
      if newValue != .ledger {
        ledgerInitialChip = .all
      }
    }
    .task {
      backfillUnfinished = await environment.mail.backfillIsUnfinished
      for await tick in environment.mailConnectionService.backfillProgress {
        backfillProgress = tick
        backfillUnfinished = await environment.mail.backfillIsUnfinished
      }
    }
    .sheet(isPresented: $isPresentingEntry) {
      // The "Add" bottom sheet. `EntryView` reads categories through `@Query`,
      // so the container has to reach it — a sheet is a new presentation
      // context and does not inherit the root's `.modelContainer`.
      EntryView(
        transactionStore: environment.transactionStore,
        categoryStore: environment.categoryStore,
        onSaved: { isPresentingEntry = false }
      )
      .modelContainer(environment.container)
    }
    .sheet(item: $presentedTransaction) { presented in
      // Home's recent-row tap, opened the same way `LedgerScreen`'s own row
      // tap already does — same reason as the entry sheet above: a new
      // presentation context needs its own `.modelContainer`.
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
      onAdd: { isPresentingEntry = true }
    )
    .onPreferenceChange(NomiTabBarHeightKey.self) { tabBarHeight = $0 }
    .padding(.horizontal, TabBarInsetHeight.sideMargin)
    .padding(.bottom, TabBarInsetHeight.bottomMargin)
  }

  /// The two halves of the bar, read from `TabBarLayout.items` so the order is
  /// written in one place. `NomiTabBar` puts the `+` between them.
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

  /// Switches to `tab`. Selecting the tab that is already showing pops its
  /// stack to the root, the usual iOS behaviour for a tab bar.
  private func select(_ tab: RootTab) {
    if tab == selection {
      popToRoot(tab)
    }
    selection = tab
  }

  /// Clears Home's stack and selects the Ledger tab (`ShowLedgerRoute`). The
  /// Ledger's own stack is left as it was.
  private func showLedger() {
    let outcome = ShowLedgerRoute.outcome()
    if outcome.clearsHomeStack {
      homePath = NavigationPath()
    }
    selection = outcome.selection
  }

  private func popToRoot(_ tab: RootTab) {
    switch tab {
    case .home: homePath = NavigationPath()
    case .ledger: ledgerPath = NavigationPath()
    case .insights: insightsPath = NavigationPath()
    case .accounts: accountsPath = NavigationPath()
    }
  }

  private func pathCount(for tab: RootTab) -> Int {
    switch tab {
    case .home: return homePath.count
    case .ledger: return ledgerPath.count
    case .insights: return insightsPath.count
    case .accounts: return accountsPath.count
    }
  }

  // MARK: - Destinations

  @ViewBuilder
  private var destination: some View {
    switch selection {
    case .home:
      NavigationStack(path: $homePath) {
        DashboardView(
          insightsStore: environment.insightsStore,
          mailConnectionService: environment.mailConnectionService,
          // Built here rather than held on `AppEnvironment`, per U17b's own
          // spec: `SwiftDataInsightsStore` and `SwiftDataRecurringStore`
          // already share `environment.cache`, so constructing this here
          // costs nothing beyond the call and shares that cache.
          recurringStore: recurringStore,
          // Stored and never read by the screen — see `DashboardView`'s note.
          // It is what makes SwiftUI re-invoke `body` after a write, and it is
          // only doing that job because it *changes*: passing a literal here
          // would compile, satisfy the parameter, and fix nothing.
          refreshToken: environment.insightsGeneration,
          onOpenReviewQueue: {
            ledgerInitialChip = .needsReview
            selection = .ledger
          },
          onSelectTransaction: { id in presentedTransaction = PresentedTransaction(id: id) }
        )
        // The back button on a pushed screen reads this title, so Home keeps it
        // even though its own nav bar is hidden by the hero.
        .navigationTitle("Home")
        .navigationDestination(for: DashboardRoute.self) { route in
          switch route {
          case .budgets:
            BudgetsScreen(budgetStore: environment.budgetStore, insightsStore: environment.insightsStore)
          case .subscriptions:
            SubscriptionsScreen(recurringStore: recurringStore)
          }
        }
        // The gear (Settings) and the mail banner or Connect mail button.
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
              // The Budgets row under Organize needs both stores; without them
              // SettingsScreen shows no row.
              budgetStore: environment.budgetStore,
              insightsStore: environment.insightsStore
            )
          case .connectMail:
            ConnectMailScreen(mailConnectionService: environment.mailConnectionService)
          }
        }
      }

    case .ledger:
      NavigationStack(path: $ledgerPath) {
        // `LedgerScreen` sets its own "Ledger" title (LG).
        LedgerScreen(
          transactionStore: environment.transactionStore,
          categoryStore: environment.categoryStore,
          accountStore: environment.accountStore,
          editor: transactionEditor,
          initialChip: ledgerInitialChip,
          suggester: environment.categorySuggester,
          // Whole-ledger search (D2). Without it the search box filters only
          // the 90-day window.
          transactionSearch: environment.transactionSearch
        )
      }

    case .insights:
      NavigationStack(path: $insightsPath) {
        // `ReportsScreen` sets its own "Insights" title.
        ReportsScreen(
          insightsStore: environment.insightsStore,
          refreshToken: environment.insightsGeneration
        )
      }

    case .accounts:
      NavigationStack(path: $accountsPath) {
        AccountsScreen(
          accountStore: environment.accountStore,
          insightsStore: environment.insightsStore
        )
      }
    }
  }
}

/// The space every tab root and every pushed screen must reserve at the bottom:
/// the bar's measured height plus its bottom margin, so content scrolls clear of
/// the bar rather than under it. A pure function, so `TabBarLayoutTests` can
/// assert the relationship directly instead of inferring it from a rendered view.
enum TabBarInsetHeight {
  /// The bar's side and bottom margins: 24 and 22 on the artboards.
  static let sideMargin: CGFloat = 24
  static let bottomMargin: CGFloat = 22

  static func reserved(barHeight: CGFloat) -> CGFloat {
    barHeight + bottomMargin
  }
}
