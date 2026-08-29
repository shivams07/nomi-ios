import Combine
import Foundation
import NomiCore
import SwiftUI

/// The permission policy, as a function.
///
/// §2.2: "Permission is requested when the user turns the toggle on in
/// Settings, never at launch. A denied permission turns the toggle back off
/// with visible copy — a toggle reading 'on' while the OS silently drops
/// notifications is worse than one reading 'off'."
///
/// Pure and separate because it is the rule, and the rest of this file is
/// plumbing around a system framework no test on this project can drive.
public enum NotificationEnablePolicy {
  /// - Parameter granted: `nil` when the request itself failed. Treated as
  ///   denied: the honest reading of "we could not establish that we may notify
  ///   you" is that we may not, and the alternative leaves the toggle on and the
  ///   promise unkept.
  public static func settings(
    after requested: NotificationSettings,
    granted: Bool?
  ) -> NotificationSettings {
    guard requested.budgetAlertsEnabled else { return requested }
    var resolved = requested
    resolved.budgetAlertsEnabled = (granted == true)
    return resolved
  }

  /// Whether turning the toggle from `old` to `new` is the transition that
  /// requires a permission request and the §2.2 suppression pass. Only
  /// off -> on qualifies: changing the threshold while already on must not
  /// re-prompt, and it must not suppress a fresh set of crossings.
  public static func isEnablingTransition(
    from old: NotificationSettings,
    to new: NotificationSettings
  ) -> Bool {
    !old.budgetAlertsEnabled && new.budgetAlertsEnabled
  }
}

/// Owns `NotificationSettings` — §2.18(3): "`SettingsScreen` takes it as a
/// `Binding`. Nothing persists it. U8 holds the source of truth and writes it."
///
/// Persisted as JSON rather than two defaults keys, because the type is
/// `Codable` and adding a third field later should not mean remembering to add
/// a third key and a third migration.
@MainActor
public final class NotificationSettingsStore: ObservableObject {
  @Published public private(set) var settings: NotificationSettings

  private let store: any KeyValueStoring
  private let scheduler: any BudgetNotificationScheduling

  /// Run after permission is *granted* on an off -> on transition. The
  /// composition root supplies the §2.2 suppression pass; this type does not
  /// know budgets exist, which is the same separation U10 keeps between its
  /// evaluator and its scheduler.
  public var onAlertsEnabled: (() async -> Void)?

  public init(store: any KeyValueStoring, scheduler: any BudgetNotificationScheduling) {
    self.store = store
    self.scheduler = scheduler
    self.settings = Self.load(from: store)
  }

  /// What `SettingsScreen` is handed. Every write to the toggle or the
  /// threshold lands in `update`, so there is one place the policy runs.
  public var binding: Binding<NotificationSettings> {
    Binding(
      get: { [weak self] in self?.settings ?? NotificationSettings() },
      set: { [weak self] newValue in self?.update(newValue) }
    )
  }

  public func update(_ newValue: NotificationSettings) {
    let previous = settings
    settings = newValue
    persist()

    guard NotificationEnablePolicy.isEnablingTransition(from: previous, to: newValue) else { return }
    Task { await requestPermissionAndEnable(newValue) }
  }

  /// `internal`, not `private`, so `NotificationSettingsStoreTests` can drive
  /// the denial path deterministically. `update` fires it in a detached `Task`,
  /// and a test that raced that task would be a test that fails on a busy
  /// machine.
  func requestPermissionAndEnable(_ requested: NotificationSettings) async {
    let granted = try? await scheduler.requestAuthorization()
    let resolved = NotificationEnablePolicy.settings(after: requested, granted: granted)

    // Only write back if the answer changed the outcome. Reassigning an
    // identical value would still publish, and republishing while Settings is
    // on screen makes the toggle visibly flicker for no reason.
    if resolved != settings {
      settings = resolved
      persist()
    }

    guard resolved.budgetAlertsEnabled else { return }
    await onAlertsEnabled?()
  }

  private func persist() {
    store.set(try? JSONEncoder().encode(settings), forKey: PreferenceKey.notificationSettings)
  }

  /// Defaults to alerts **off**. Not a neutral choice: the app must never be in
  /// a state where it believes it may notify without having asked, and a fresh
  /// install has asked nobody.
  private static func load(from store: any KeyValueStoring) -> NotificationSettings {
    guard
      let data = store.data(forKey: PreferenceKey.notificationSettings),
      let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data)
    else {
      return NotificationSettings()
    }
    return decoded
  }
}
