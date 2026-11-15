import NomiCore
import SwiftUI

/// A shell action with no payload: presents a sheet, selects a tab, and so on.
/// The root sets it with one of the environment keys below; a caller with no root
/// sees nil and hides its control.
public struct NomiShellAction: Sendable {
  private let run: @MainActor @Sendable () -> Void

  public init(_ run: @escaping @MainActor @Sendable () -> Void) {
    self.run = run
  }

  @MainActor
  public func callAsFunction() {
    run()
  }
}

private struct NomiOpenReviewKey: EnvironmentKey {
  static let defaultValue: NomiShellAction? = nil
}

private struct NomiShowPlanKey: EnvironmentKey {
  static let defaultValue: NomiShellAction? = nil
}

private struct NomiOpenImportKey: EnvironmentKey {
  static let defaultValue: NomiShellAction? = nil
}

/// The stores are existentials, so their defaults are computed rather than stored:
/// a stored `any` default would need `Sendable`, which these protocols do not promise.
private struct NomiRuleStoreKey: EnvironmentKey {
  static var defaultValue: (any RuleStore)? { nil }
}

private struct NomiInsightsStoreKey: EnvironmentKey {
  static var defaultValue: (any InsightsStore)? { nil }
}

public extension EnvironmentValues {
  /// Presents the Review queue full screen (`ReviewQueueScreen`).
  var nomiOpenReview: NomiShellAction? {
    get { self[NomiOpenReviewKey.self] }
    set { self[NomiOpenReviewKey.self] = newValue }
  }

  /// Selects the Plan tab.
  var nomiShowPlan: NomiShellAction? {
    get { self[NomiShowPlanKey.self] }
    set { self[NomiShowPlanKey.self] = newValue }
  }

  /// Dismisses any sheet, selects Home and pushes the Import screen.
  var nomiOpenImport: NomiShellAction? {
    get { self[NomiOpenImportKey.self] }
    set { self[NomiOpenImportKey.self] = newValue }
  }

  /// The rule store, for screens that present the rule editor from a sheet.
  var nomiRuleStore: (any RuleStore)? {
    get { self[NomiRuleStoreKey.self] }
    set { self[NomiRuleStoreKey.self] = newValue }
  }

  /// The insights store, for screens that open a sheet and need the same reads.
  var nomiInsightsStore: (any InsightsStore)? {
    get { self[NomiInsightsStoreKey.self] }
    set { self[NomiInsightsStoreKey.self] = newValue }
  }
}
