import Foundation

/// The four destinations the tab bar selects between.
///
/// **Accounts and Budgets are deliberately absent.** §2.18: "Accounts and
/// Budgets hang off Dashboard/Settings, not off the bar." They are pushed onto
/// the enclosing `NavigationStack`, which is also why every tab has one.
public enum RootTab: String, CaseIterable, Sendable, Identifiable {
  case dashboard
  case ledger
  case reports
  case settings

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .dashboard: return "Home"
    case .ledger: return "Ledger"
    case .reports: return "Reports"
    case .settings: return "Settings"
    }
  }

  public var symbolName: String {
    switch self {
    case .dashboard: return "house"
    case .ledger: return "list.bullet"
    case .reports: return "chart.bar"
    case .settings: return "gearshape"
    }
  }
}

/// One slot in the bar. The centre `+` is not a tab — it presents the entry
/// sheet ("**Add** — bottom sheet, radius 24", design §"The screens,
/// re-skinned") and selects nothing — so it cannot be a `RootTab` case without
/// making every `switch` over destinations carry an impossible branch.
public enum TabBarItem: Equatable, Sendable, Identifiable {
  case tab(RootTab)
  case add

  public var id: String {
    switch self {
    case .tab(let tab): return tab.rawValue
    case .add: return "add"
    }
  }
}

public enum TabBarLayout {
  /// Bar order, verbatim from §2.18: "Dashboard, Ledger, centre `+`, Reports,
  /// Settings". The `+` is third of five, which is what makes it the centre —
  /// asserted in `RootTabTests` rather than left to whoever edits this array
  /// next.
  public static let items: [TabBarItem] = [
    .tab(.dashboard),
    .tab(.ledger),
    .add,
    .tab(.reports),
    .tab(.settings),
  ]
}
