import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// FU-1's pure rules: the environment default is nil (a no-op for previews and
/// tests), the action runs what the root gave it, and the two Ledger controls
/// are drawn only while the action is wired. Swift-testing, so the CLT harness
/// runs them too (V2).
@Suite("Show Ledger")
struct NomiShowLedgerTests {
  /// A counter the action's closure can bump. Main-actor bound, as the action is.
  @MainActor
  private final class Counter {
    var count = 0
  }

  @Test("the environment value defaults to nil, so nothing is wired and nothing runs")
  func defaultIsNil() {
    let values = EnvironmentValues()
    #expect(values.nomiShowLedger == nil)
  }

  @Test("a wired environment value is read back as wired")
  func wiredValueRoundTrips() {
    var values = EnvironmentValues()
    values.nomiShowLedger = NomiShowLedgerAction {}
    #expect(values.nomiShowLedger != nil)
  }

  @Test("the action runs the closure the root gave it, once per call")
  @MainActor
  func actionRunsItsClosure() {
    let counter = Counter()
    let action = NomiShowLedgerAction { counter.count += 1 }
    action()
    action()
    #expect(counter.count == 2)
  }

  @Test("the control is drawn when the action is wired")
  func controlShowsWhenWired() {
    #expect(NomiShowLedgerLogic.showsControl(isWired: true))
  }

  @Test("the control is hidden when the action is not wired")
  func controlHiddenWhenNotWired() {
    #expect(!NomiShowLedgerLogic.showsControl(isWired: false))
  }

  /// Records each request the action hands its closure, in order.
  @MainActor
  private final class RequestLog {
    var requests: [ActivityRequest] = []
  }

  @Test("the zero-argument call runs the closure as .all")
  @MainActor
  func zeroArgumentIsAll() {
    let log = RequestLog()
    let action = NomiShowLedgerAction { request in log.requests.append(request) }
    action()
    #expect(log.requests == [.all])
  }

  @Test("a request reaches the closure unchanged, including a category")
  @MainActor
  func requestReachesTheClosure() {
    let log = RequestLog()
    let categoryID = UUID()
    let action = NomiShowLedgerAction { request in log.requests.append(request) }
    action(.toReview)
    action(.uncategorized)
    action(.category(categoryID))
    #expect(log.requests == [.toReview, .uncategorized, .category(categoryID)])
  }

  @Test("a zero-argument closure still runs for the zero-argument call")
  @MainActor
  func zeroArgumentClosureStillRuns() {
    let counter = Counter()
    let action = NomiShowLedgerAction { counter.count += 1 }
    action()
    #expect(counter.count == 1)
  }

  @Test("the activity request defaults to nil on the environment")
  func activityRequestDefaultsToNil() {
    let values = EnvironmentValues()
    #expect(values.nomiActivityRequest == nil)
  }
}
