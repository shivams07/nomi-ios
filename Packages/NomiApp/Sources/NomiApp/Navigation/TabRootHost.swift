import SwiftUI

/// Everything a tab root's body reads from `RootView`. `TabRootHost` rebuilds its content
/// only when this key changes, so each field must move on every input that root reads,
/// and on nothing else (F3c). A push or pop changes `pathCount`, a route request changes
/// `requestID` (Activity only), a cache change moves the root's refresh token, and
/// `isRequestingPermission` drives Plan's notification row while the OS prompt is up.
struct TabRootKey: Equatable {
  let tab: RootTab
  let isSelected: Bool
  let refreshToken: Int
  let pathCount: Int
  let requestID: Int
  let reserve: CGFloat
  let isRequestingPermission: Bool

  /// The key for `tab` as `RootView` sees it now. Only Activity carries a request id, so
  /// a new Activity request changes Activity's key and no other tab's.
  static func make(
    tab: RootTab,
    selection: RootTab,
    tokens: RouteTokens,
    pathCount: Int,
    activityRequestID: Int,
    reserve: CGFloat,
    isRequestingPermission: Bool
  ) -> TabRootKey {
    TabRootKey(
      tab: tab,
      isSelected: tab == selection,
      refreshToken: tokens.token(for: tab),
      pathCount: pathCount,
      requestID: tab == .activity ? activityRequestID : 0,
      reserve: reserve,
      isRequestingPermission: isRequestingPermission)
  }
}

extension RouteTokens {
  /// The refresh token the tab root's key carries: the one its route reads.
  func token(for tab: RootTab) -> Int {
    switch tab {
    case .home: return dashboard
    case .activity: return ledger
    case .insights: return reports
    case .plan: return plan
    }
  }
}

/// A tab root that is rebuilt only when its `TabRootKey` changes. A switch changes two
/// keys (the old tab's and the new one's), so the other kept tabs are not re-evaluated.
/// Opacity and hit testing follow `key.isSelected` here, so the body owns the hidden state.
struct TabRootHost<Content: View>: View, Equatable {
  let key: TabRootKey
  let content: () -> Content

  init(key: TabRootKey, @ViewBuilder content: @escaping () -> Content) {
    self.key = key
    self.content = content
  }

  static func == (lhs: TabRootHost<Content>, rhs: TabRootHost<Content>) -> Bool {
    lhs.key == rhs.key
  }

  var body: some View {
    content()
      .opacity(key.isSelected ? 1 : 0)
      .allowsHitTesting(key.isSelected)
      .accessibilityHidden(!key.isSelected)
  }
}
