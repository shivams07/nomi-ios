import Foundation
import NomiCore

/// The budget-alert toggle's displayed state. When notification permission is
/// denied at the OS level, the toggle renders OFF with an explanatory row —
/// never on-but-silent, which would look like alerts are active when nothing
/// can actually fire.
enum NotificationToggleDisplay {
  static func isOn(settings: NotificationSettings, permissionDenied: Bool) -> Bool {
    settings.budgetAlertsEnabled && !permissionDenied
  }

  static func showsPermissionExplanation(permissionDenied: Bool) -> Bool {
    permissionDenied
  }
}

/// The "iCloud sync" row (B11).
///
/// The app falls back to a local-only store when the CloudKit container will
/// not construct, which is correct — but until now it announced that with a
/// `print`, so the only person who could tell was one with Xcode attached. A
/// user in that state has an app that works and simply never appears on their
/// second device.
enum StorageModeDisplay {
  static func text(for mode: StorageMode) -> String {
    mode.isSyncing ? "On" : "Off — this device only"
  }

  /// The caption under the row. `nil` when syncing, so the row renders as one
  /// line and nothing is said where there is nothing to say.
  ///
  /// The reason is the underlying error's description: developer-shaped text,
  /// deliberately. A user who can read it out loud gives a usable report, and
  /// a hand-written friendly string would have to guess at causes this code
  /// does not know.
  static func caption(for mode: StorageMode) -> String? {
    guard let reason = mode.reason else { return nil }
    return "Your data is safe on this device, but it is not syncing to iCloud. \(reason)"
  }
}

/// The re-scan action, pulled out so it is spy-testable: it must call
/// `syncNow()` and nothing else — specifically never `disconnect()` followed
/// by `connect()`, which the U7 notes call out explicitly as the wrong shape.
enum SettingsActions {
  @discardableResult
  static func rescan(using service: MailConnectionService) async throws -> SyncSummary {
    try await service.syncNow()
  }
}

/// The unmatched-sender rows shown after a manual re-scan (§2.5.1,
/// `ui-unmatched-senders`). Domain and count only — `UnmatchedSender` cannot
/// carry a full address, but the guard is repeated here at the display layer.
/// An empty list renders as no rows, never an empty section — the screen
/// decides whether to show the section at all from this same emptiness.
enum UnmatchedSenderDisplay {
  static func rows(for senders: [UnmatchedSender]) -> [String] {
    senders.map { "\($0.domain) — \($0.count)" }
  }
}
