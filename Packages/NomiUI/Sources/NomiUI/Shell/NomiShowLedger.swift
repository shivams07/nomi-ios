import SwiftUI

// clt-harness: include

/// Switches the app to the Ledger tab and clears Home's stack, so no pushed
/// screen is left over it. The root sets it with `\.nomiShowLedger`; NomiUI only
/// calls it (FU-1: Home "See all" and Import "View in Ledger").
public struct NomiShowLedgerAction: Sendable {
  private let run: @MainActor @Sendable () -> Void

  public init(_ run: @escaping @MainActor @Sendable () -> Void) {
    self.run = run
  }

  @MainActor
  public func callAsFunction() {
    run()
  }
}

private struct NomiShowLedgerActionKey: EnvironmentKey {
  static let defaultValue: NomiShowLedgerAction? = nil
}

public extension EnvironmentValues {
  /// The "show the Ledger" action. It defaults to nil, which is a no-op for
  /// anything that reads it: the "See all" and "View in Ledger" controls are
  /// hidden while it is nil, so previews and tests compile without a root.
  var nomiShowLedger: NomiShowLedgerAction? {
    get { self[NomiShowLedgerActionKey.self] }
    set { self[NomiShowLedgerActionKey.self] = newValue }
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
