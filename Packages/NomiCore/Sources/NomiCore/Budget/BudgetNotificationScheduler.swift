import Foundation

#if canImport(UserNotifications)
  import UserNotifications
#endif

/// The seam that keeps `BudgetAlertEvaluator`'s tests free of
/// `UNUserNotificationCenter` (design §2.2). Everything above this protocol is
/// pure and testable; everything below it is a system framework we cannot drive
/// from CI.
public protocol BudgetNotificationScheduling: Sendable {
  /// Requests permission. The *policy* around the answer — turning the Settings
  /// toggle back off with visible copy when it is `false` — is U8's, not this
  /// wrapper's.
  @discardableResult func requestAuthorization() async throws -> Bool
  /// Presents one alert. Suppressed alerts must never reach here.
  func schedule(_ alert: BudgetAlert) async throws
}

public enum BudgetNotificationError: Error, Sendable, Equatable {
  /// Raised rather than silently dropping the alert: a suppressed alert
  /// arriving here means the caller lost track of §2.2's opt-in rule, and a
  /// notification the user was promised they would not get is worth a crash
  /// report in dev, not a shrug.
  case suppressedAlertMustNotBeScheduled
  /// The platform has no `UserNotifications` framework. Not reachable on iOS.
  case unavailableOnThisPlatform
}

/// A thin `UNUserNotificationCenter` wrapper. It holds no state and touches the
/// center lazily, so merely constructing one is safe in a test binary — which
/// matters, because `UNUserNotificationCenter.current()` traps in a process with
/// no bundle. Nothing in this package's tests calls its methods; it is
/// compile-verified only, the same standing this project gives every other
/// system-framework boundary.
public struct BudgetNotificationScheduler: BudgetNotificationScheduling {
  private let categoryIdentifier = "nomi.budget-alert"

  public init() {}

  @discardableResult
  public func requestAuthorization() async throws -> Bool {
    #if canImport(UserNotifications)
      return try await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .sound, .badge])
    #else
      throw BudgetNotificationError.unavailableOnThisPlatform
    #endif
  }

  public func schedule(_ alert: BudgetAlert) async throws {
    guard !alert.wasSuppressed else {
      throw BudgetNotificationError.suppressedAlertMustNotBeScheduled
    }

    #if canImport(UserNotifications)
      let content = UNMutableNotificationContent()
      content.title = alert.categoryName
      content.body = Self.body(for: alert)
      content.categoryIdentifier = categoryIdentifier
      content.sound = .default

      // `logKey` as the request identifier: if the same alert somehow reaches
      // the center twice, iOS replaces rather than stacks it.
      let request = UNNotificationRequest(
        identifier: alert.logKey,
        content: content,
        trigger: nil  // deliver now
      )
      try await UNUserNotificationCenter.current().add(request)
    #else
      throw BudgetNotificationError.unavailableOnThisPlatform
    #endif
  }

  /// Percentage only, deliberately. Money formatting lives in NomiUI's
  /// `NomiFormatters` and NomiCore cannot depend on NomiUI; re-implementing the
  /// grouping and the ₹ rule here would be a second formatter to keep in step.
  /// Adding the amount later is a one-line change at a known place.
  static func body(for alert: BudgetAlert) -> String {
    let percent = Int((alert.fraction * 100).rounded(.down))
    if alert.fraction >= 1 {
      return "You're over budget — \(percent)% spent."
    }
    return "You've used \(percent)% of this month's budget."
  }
}
