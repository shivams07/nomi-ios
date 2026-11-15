import SwiftUI

// clt-harness: include

/// Which filter the Activity tab opens with (F3b, I-15). The root sets it through
/// `NomiShowLedgerAction`, and `RootView` turns it into the Activity chip.
public enum ActivityRequest: Equatable, Sendable {
  case all
  case toReview
  case uncategorized
  case category(UUID)
  case search(String)
}

/// Switches the app to the Activity tab and clears Home's stack, so no pushed
/// screen is left over it. The root sets it with `\.nomiShowLedger`; NomiUI only
/// calls it (FU-1: Home "See all" and Import "View in Activity").
public struct NomiShowLedgerAction: Sendable {
  private let run: @MainActor @Sendable (ActivityRequest) -> Void

  /// Runs `run` with the request the caller made.
  public init(_ run: @escaping @MainActor @Sendable (ActivityRequest) -> Void) {
    self.run = run
  }

  /// For a caller that only shows the tab. The closure runs for `.all`.
  public init(_ run: @escaping @MainActor @Sendable () -> Void) {
    self.run = { _ in run() }
  }

  /// Opens Activity with no filter. Same as `callAsFunction(.all)`.
  @MainActor
  public func callAsFunction() {
    run(.all)
  }

  @MainActor
  public func callAsFunction(_ request: ActivityRequest) {
    run(request)
  }
}

private struct NomiShowLedgerActionKey: EnvironmentKey {
  static let defaultValue: NomiShowLedgerAction? = nil
}

private struct NomiActivityRequestKey: EnvironmentKey {
  static let defaultValue: ActivityRequest? = nil
}

public extension EnvironmentValues {
  /// The "show the Ledger" action. It defaults to nil, which is a no-op for
  /// anything that reads it: the "See all" and "View in Activity" controls are
  /// hidden while it is nil, so previews and tests compile without a root.
  var nomiShowLedger: NomiShowLedgerAction? {
    get { self[NomiShowLedgerActionKey.self] }
    set { self[NomiShowLedgerActionKey.self] = newValue }
  }

  /// The request the Activity stack was opened with. `RootView` sets it on the
  /// Activity stack only; nil everywhere else.
  var nomiActivityRequest: ActivityRequest? {
    get { self[NomiActivityRequestKey.self] }
    set { self[NomiActivityRequestKey.self] = newValue }
  }
}

/// Whether the two Ledger controls are drawn. Pure, so the rule is a tested fact
/// and each view does not decide it separately.
public enum NomiShowLedgerLogic {
  /// A control is drawn only when the root has wired the action.
  public static func showsControl(isWired: Bool) -> Bool {
    isWired
  }
}
