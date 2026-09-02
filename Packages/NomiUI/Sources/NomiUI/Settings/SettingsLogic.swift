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
