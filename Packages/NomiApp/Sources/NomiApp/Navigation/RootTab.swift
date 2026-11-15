// clt-harness: include

import Foundation

/// The four destinations the tab bar selects between: Home, Activity, Insights
/// and Plan (I-15; the approved canvas, icon-only bar).
///
/// **Budgets, Accounts and Settings are deliberately absent.** Budgets is a card on
/// Home and a card on Plan. Accounts is a row in Settings > Organize. Settings is
/// pushed from Home's gear, so it has a back button and is not a slot. The pushed
/// screens sit on Home's stack, which is why each tab keeps its own
/// `NavigationStack`: a shared stack would carry a push from one tab into another.
public enum RootTab: String, CaseIterable, Sendable, Identifiable {
  case home
  case activity
  case insights
  case plan

  public var id: String { rawValue }

  /// The accessibility label. The bar draws icons only.
  public var title: String {
    switch self {
    case .home: return "Home"
    case .activity: return "Activity"
    case .insights: return "Insights"
    case .plan: return "Plan"
    }
  }

  /// SF Symbols, as the canvas draws them: house, the activity lines, the bar
  /// chart, the target.
  public var symbolName: String {
    switch self {
    case .home: return "house"
    case .activity: return "text.alignleft"
    case .insights: return "chart.bar"
    case .plan: return "target"
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
  /// Bar order, from the canvas: "Home, Activity, +, Insights, Plan". The `+` is
  /// third of five, which is what makes it the centre. `TabBarOrderTests` and
  /// `NavigationTests` assert this list, so an edit that moves the `+` fails a test
  /// rather than shipping.
  public static let items: [TabBarItem] = [
    .tab(.home),
    .tab(.activity),
    .add,
    .tab(.insights),
    .tab(.plan),
  ]
}

/// Whether the tab bar is on screen. It shows only on a tab root: once a screen
/// is pushed (Settings from Home's gear, Budgets, Subscriptions, Connect mail)
/// the bar goes, and the screen's own back button takes over.
public enum TabBarVisibility {
  public static func isVisible(pathCount: Int) -> Bool {
    pathCount == 0
  }
}
