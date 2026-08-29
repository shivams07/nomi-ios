import NomiCore
import NomiUI
import SwiftUI

/// The navigation graph. §2.18(1): "There is no `TabView` anywhere in the
/// repository. Twelve public screens are built and reachable by name; nothing
/// composes them."
///
/// **Not a `TabView`, deliberately.** U5 shipped the chrome this app is meant
/// to wear — `NomiTabShell` (glow orbs once, behind everything) and
/// `NomiFloatingTabBarBackground` (the floating glass pill). A `TabView` draws
/// its own opaque bar and pins content above it; getting U5's bar to sit over
/// that means hiding the system one and fighting its safe-area insets. A
/// `ZStack` over an explicit selection is less machinery, and it is the only
/// arrangement in which `NomiFloatingTabBarBackground` — which currently has no
/// consumer at all — actually gets used.
///
/// One `NavigationStack` per tab, not one around the bar. Accounts and Budgets
/// push onto Dashboard's and Settings' stacks respectively (§2.18: they "hang
/// off Dashboard/Settings, not off the bar"), and a shared stack would carry a
/// push from one tab into another.
struct RootView: View {
  @ObservedObject var environment: AppEnvironment
  @State private var selection: RootTab = .dashboard
  @State private var isPresentingEntry = false

  var body: some View {
    NomiTabShell {
      ZStack(alignment: .bottom) {
        destination
        NomiFloatingTabBar(selection: $selection, onAdd: { isPresentingEntry = true })
          .padding(.horizontal, NomiSpacing.screenGutter)
          .padding(.bottom, NomiSpacing.xs)
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
  }

  @ViewBuilder
  private var destination: some View {
    switch selection {
    case .dashboard:
      NavigationStack {
        DashboardView(
          insightsStore: environment.insightsStore,
          mailConnectionService: environment.mailConnectionService
        )
        .navigationTitle("Home")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            // Accounts hangs off Dashboard, per §2.18. A toolbar link rather
            // than a tab.
            NavigationLink {
              AccountsScreen(
                accountStore: environment.accountStore,
                insightsStore: environment.insightsStore
              )
            } label: {
              Image(systemName: "creditcard")
            }
          }
        }
      }

    case .ledger:
      NavigationStack {
        LedgerScreen(
          transactionStore: environment.transactionStore,
          categoryStore: environment.categoryStore
        )
        // `LedgerScreen` is a tab-root screen and sets no title of its own —
        // same as `DashboardView`, and the same reason Dashboard and Reports
        // get theirs here.
        .navigationTitle("Ledger")
      }

    case .reports:
      NavigationStack {
        ReportsScreen(insightsStore: environment.insightsStore)
          .navigationTitle("Reports")
      }

    case .settings:
      NavigationStack {
        SettingsScreen(
          mailConnectionService: environment.mailConnectionService,
          fileImportService: environment.fileImportService,
          categoryStore: environment.categoryStore,
          ruleStore: environment.ruleStore,
          notificationSettings: environment.notificationSettings.binding
        )
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            // Budgets hangs off Settings, per §2.18.
            //
            // `SettingsScreen` already self-routes to Categories and Rules with
            // its own `NavigationLink`s and §2.18 says in as many words not to
            // re-route it — so Budgets goes in the toolbar rather than being
            // added as a fifth row inside a screen this unit does not own.
            NavigationLink {
              BudgetsScreen(
                budgetStore: environment.budgetStore,
                insightsStore: environment.insightsStore
              )
            } label: {
              Image(systemName: "chart.pie")
            }
          }
        }
      }
    }
  }
}

/// The floating glass pill bar, over U5's `NomiFloatingTabBarBackground`.
///
/// The centre `+` is a solid blue circle — Estate-Ease's send button doing a
/// different job (design §"The screens, re-skinned") — and it is the one place
/// in this file that uses `NomiColor.accent`. `DESIGN.md`'s "one primary action
/// per screen, always blue" is why nothing else here is.
struct NomiFloatingTabBar: View {
  @Binding var selection: RootTab
  let onAdd: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      ForEach(TabBarLayout.items) { item in
        switch item {
        case .tab(let tab):
          tabButton(tab)
        case .add:
          addButton
        }
      }
    }
    .padding(.vertical, NomiSpacing.xs)
    .padding(.horizontal, NomiSpacing.xs)
    .background(NomiFloatingTabBarBackground())
  }

  private func tabButton(_ tab: RootTab) -> some View {
    Button {
      selection = tab
    } label: {
      VStack(spacing: NomiSpacing.xxs) {
        Image(systemName: tab.symbolName)
          .font(.system(size: 18, weight: selection == tab ? .semibold : .regular))
        Text(tab.title)
          .nomiTextStyle(.caption)
      }
      // Selection is carried by opacity, not hue: the accent is the `+`
      // button's and a second blue in the bar would make two primary actions.
      .foregroundStyle(selection == tab ? NomiColor.textPrimary : NomiColor.textQuaternary)
      .frame(maxWidth: .infinity)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(tab.title)
    .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
  }

  private var addButton: some View {
    Button(action: onAdd) {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(NomiColor.textPrimary)
        .frame(width: 44, height: 44)
        .background(Circle().fill(NomiColor.accent))
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityLabel("Add transaction")
  }
}
