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

/// The "iCloud sync" row (B11, then U9b).
///
/// The app falls back to a local-only store when the CloudKit container will
/// not construct, and it *pauses* sync when there is no usable iCloud account.
/// Until B11 it announced neither, so a user in either state had an app that
/// worked and simply never appeared on their second device.
///
/// The two are worth distinguishing to the user because the fix differs:
/// `.localOnly` needs a relaunch to regain sync, `.cloudKitPaused` resumes on
/// its own as soon as an account is available.
enum StorageModeDisplay {
  /// The value on the right of the row.
  ///
  /// `.temporarilyUnavailable` is the one paused state that does not read
  /// "Off", because it is the one expected to resolve without the user doing
  /// anything — telling them sync is off would invite them to go fix something
  /// that is not broken.
  static func text(for mode: StorageMode) -> String {
    switch mode {
    case .cloudKit: return "On"
    case .localOnly: return "Off — this device only"
    case .cloudKitPaused(.noAccount): return "Off — not signed in to iCloud"
    case .cloudKitPaused(.restricted): return "Off — iCloud restricted"
    case .cloudKitPaused(.temporarilyUnavailable): return "Waiting for iCloud"
    case .cloudKitPaused(.couldNotDetermine): return "Off — iCloud status unknown"
    }
  }

  /// The caption under the row. `nil` when syncing, so the row renders as one
  /// line and nothing is said where there is nothing to say.
  ///
  /// **Every non-syncing caption opens by saying the data is safe**, because
  /// the report this row exists to prevent is "the app lost my transactions"
  /// — which is what a user concludes when their second device is empty. The
  /// reassurance has to come before the explanation, not after it.
  ///
  /// `.localOnly` and `.couldNotDetermine` end in developer-shaped text,
  /// deliberately: a user who can read it out gives a usable report, and a
  /// hand-written friendly string would have to guess at causes this code does
  /// not know. The other paused reasons are known exactly, so they get a
  /// sentence written for a person, and `.noAccount` names where to go.
  static func caption(for mode: StorageMode) -> String? {
    switch mode {
    case .cloudKit:
      return nil
    case .localOnly(let reason):
      return "Your data is safe on this device, but it is not syncing to iCloud. \(reason)"
    case .cloudKitPaused(.noAccount):
      return "Your data is safe on this device. Sign in to iCloud in the Settings app to sync."
    case .cloudKitPaused(.restricted):
      return
        "Your data is safe on this device. iCloud is restricted on this device (Screen Time or a management profile)."
    case .cloudKitPaused(.temporarilyUnavailable):
      return
        "Your data is safe on this device. iCloud is temporarily unavailable — syncing resumes on its own."
    case .cloudKitPaused(.couldNotDetermine(let detail)):
      return "Your data is safe on this device. \(detail)"
    }
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

  /// M7: "Scan last 6 months" — a manual backfill trigger, distinct from
  /// Force Re-scan's incremental `syncNow()`. Six months is fixed, not user
  /// configurable, the same window `BackfillScreen`'s onboarding scan offers.
  @discardableResult
  static func scanRecent(using service: MailConnectionService) async throws -> SyncSummary {
    try await service.startBackfill(months: 6)
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
