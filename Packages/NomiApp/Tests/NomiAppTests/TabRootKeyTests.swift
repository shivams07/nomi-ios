import CoreGraphics
import Testing
@testable import NomiApp

/// F3c step 4. An equatable tab root is rebuilt only when its key changes, so the key must
/// move on every input that root reads, and on nothing else.
@Suite("Tab root keys")
struct TabRootKeyTests {
  private let tokens = RouteTokens(generation: 0)

  private func key(
    _ tab: RootTab, selection: RootTab = .home, tokens: RouteTokens? = nil, pathCount: Int = 0,
    requestID: Int = 0, reserve: CGFloat = 80, permission: Bool = false
  ) -> TabRootKey {
    TabRootKey.make(
      tab: tab, selection: selection, tokens: tokens ?? self.tokens, pathCount: pathCount,
      activityRequestID: requestID, reserve: reserve, isRequestingPermission: permission)
  }

  @Test("switching selection between two other tabs leaves a third tab's key equal")
  func unrelatedSelectionKeepsKey() {
    #expect(key(.plan, selection: .home) == key(.plan, selection: .insights))
  }

  @Test("a push on Home changes Home's key")
  func pushChangesHome() {
    #expect(key(.home, pathCount: 0) != key(.home, pathCount: 1))
  }

  @Test("a new Activity request changes Activity's key only")
  func requestChangesActivityOnly() {
    #expect(key(.activity, requestID: 0) != key(.activity, requestID: 1))
    #expect(key(.home, requestID: 0) == key(.home, requestID: 1))
  }

  @Test("a cache generation change changes every key")
  func generationChangesEveryKey() {
    let next = RouteTokens(generation: 1)
    for tab in RootTab.allCases {
      #expect(key(tab) != key(tab, tokens: next), "\(tab) key must follow the cache generation")
    }
  }

  @Test("Plan's permission prompt state changes Plan's key")
  func permissionChangesPlan() {
    #expect(key(.plan, permission: false) != key(.plan, permission: true))
  }

  @Test("the selected tab's key differs from the same tab when it is not selected")
  func selectionChangesOwnKey() {
    #expect(key(.insights, selection: .insights) != key(.insights, selection: .home))
  }
}
