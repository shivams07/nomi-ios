// clt-harness: include

import Foundation

/// The four destinations the tab bar selects between: Home, Ledger, Insights
/// and Accounts (SIMP §0, "Five slots"; the four tab artboards).
///
/// **Budgets and Settings are deliberately absent.** Budgets is a card on Home
/// and a row in Settings > Organize. Settings is pushed from Home's gear, so it
/// has a back button and is not a slot. Both are pushed onto the Home stack,
/// which is why each tab keeps its own `NavigationStack`: a shared stack would
/// carry a push from one tab into another.
public enum RootTab: String, CaseIterable, Sendable, Identifiable {
  case home
  case ledger
  case insights
  case accounts

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .home: return "Home"
    case .ledger: return "Ledger"
    case .insights: return "Insights"
    case .accounts: return "Accounts"
    }
  }

  /// SF Symbols. Each one matches the glyph the artboard draws: house, the
  /// ledger arrows, the pie, the card.
  public var symbolName: String {
    switch self {
    case .home: return "house"
    case .ledger: return "arrow.up.arrow.down"
    case .insights: return "chart.pie"
    case .accounts: return "creditcard"
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
  /// Bar order, verbatim from the four tab artboards: "Home, Ledger, +,
  /// Insights, Accounts". The `+` is third of five, which is what makes it the
  /// centre. `TabBarOrderTests` and `NavigationTests` assert this list, so an
  /// edit that moves the `+` fails a test rather than shipping.
  public static let items: [TabBarItem] = [
    .tab(.home),
    .tab(.ledger),
    .add,
    .tab(.insights),
    .tab(.accounts),
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
