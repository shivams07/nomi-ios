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
}
