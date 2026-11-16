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

/// The "iCloud sync" row (B11, then U9b, then S9a).
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
    case .inMemory: return "Off — not being saved"
    case .cloudKitPaused(.noAccount): return "Off — not signed in to iCloud"
    case .cloudKitPaused(.restricted): return "Off — iCloud restricted"
    case .cloudKitPaused(.temporarilyUnavailable): return "Waiting for iCloud"
    case .cloudKitPaused(.couldNotDetermine): return "Off — iCloud status unknown"
    }
  }

  /// The caption under the row. `nil` when syncing, so the row renders as one
  /// line and nothing is said where there is nothing to say.
  ///
  /// **Every non-syncing caption except `.inMemory` and `.localOnly` opens by
  /// saying the data is safe**, because the report this row exists to prevent is
  /// "the app lost my transactions" — which is what a user concludes when their
  /// second device is empty. The reassurance has to come before the explanation.
  /// `.inMemory` says the opposite, so its reason is shown alone.
  ///
  /// `.localOnly` (S9a step 4) is a plain sentence that says everything is kept on
  /// this iPhone. Its reason is developer text, so it goes to "Copy details" (see
  /// `SettingsLogic.copyableDetails`), not into the caption.
  ///
  /// `.couldNotDetermine` still ends in its detail, deliberately: a user who can
  /// read it out gives a usable report.
  static func caption(for mode: StorageMode) -> String? {
    switch mode {
    case .cloudKit:
      return nil
    case .localOnly:
      return "Nomi couldn’t start iCloud sync, so everything is kept on this iPhone."
    case .inMemory(let reason):
      return reason
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

/// The R7 notice shown in Settings after the app moved an unopenable store
/// aside and started a fresh one. Pure copy, so it can be tested without
/// rendering.
enum StoreRecoveryDisplay {
  /// The notice's body. The date is a calendar day in the device's zone, in
  /// en_IN, and the formatter is given its calendar and zone explicitly so a
  /// process in another zone cannot shift the day.
  static func caption(for notice: StoreRecoveryNotice) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_IN")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .current
    formatter.dateFormat = "d MMM yyyy"
    let day = formatter.string(from: notice.movedAt)
    return
      "Nomi couldn’t open its saved data on \(day), so it started fresh. The old data was kept on this device as \(notice.fileName)."
  }
}

/// ST copy that the Settings screen builds from data, kept pure so it can be
/// tested without rendering.
enum SettingsLogic {
  /// The attention row's title when mail is not connected (artboard states
  /// ST Edges). `nil` for `.connected`, which shows the address and status
  /// instead.
  static func attentionTitle(for state: MailConnectionState) -> String? {
    switch state {
    case .connected: return nil
    case .disconnected: return "Mail disconnected"
    case .connecting: return "Connecting…"
    case .failed: return "Couldn’t reach your mail"
    }
  }

  /// "Mail alerts" is On only while the mail connection is live.
  static func mailIsOn(_ state: MailConnectionState) -> Bool {
    if case .connected = state { return true }
    return false
  }

  /// The address the row shows on its own line when mail is connected. A single long
  /// word, so the row gives it its own line and scales it rather than breaking it.
  static func mailAddress(for state: MailConnectionState) -> String? {
    if case .connected(let address, _) = state { return address }
    return nil
  }

  /// The status line under the address: when mail was last checked. Not connected, it is
  /// the same words as the attention title, so the row and the mail screen agree.
  static func mailStatus(for state: MailConnectionState, now: Date) -> String {
    if case .connected(_, let lastSync) = state {
      guard let lastSync else { return "not checked yet" }
      return "checked \(SyncStatusRow.relativeSyncPhrase(lastSync, now: now))"
    }
    return attentionTitle(for: state) ?? ""
  }

  /// The row's caption as one line of text: the address, then the status.
  static func mailAlertsCaption(for state: MailConnectionState, now: Date) -> String {
    guard let address = mailAddress(for: state) else { return mailStatus(for: state, now: now) }
    return "\(address) · \(mailStatus(for: state, now: now))"
  }

  /// The Budget alerts row's caption, read from the threshold the app actually uses.
  static func budgetAlertsCaption(thresholdFraction: Double) -> String {
    let percent = Int((thresholdFraction * 100).rounded())
    return "At \(percent)% and when you go over"
  }

  /// "1 category", "14 categories". The plural comes from the string catalog (G9).
  static func categoriesText(count: Int) -> String {
    String(localized: "\(count) categories", bundle: .module)
  }

  /// "Auto-categorise" counts the rules the user made that are switched on. System
  /// rules and switched-off rules are not merchants remembered.
  static func merchantsRemembered(_ rules: [(isSystem: Bool, isEnabled: Bool)]) -> Int {
    rules.filter { !$0.isSystem && $0.isEnabled }.count
  }

  static func merchantsRememberedText(count: Int) -> String {
    String(localized: "\(count) merchants remembered", bundle: .module)
  }

  /// "3 accounts · ₹1,18,481.00 estimated". The total is signed through the same rule
  /// the Accounts screen uses.
  static func accountsText(count: Int, totalMinor: Int) -> String {
    let plural = String(localized: "\(count) accounts", bundle: .module)
    var amount = TrackedBalanceText.string(minor: totalMinor)
    // A word joiner keeps "-" with "₹" when the line wraps at accessibility sizes.
    if amount.hasPrefix("-") { amount.insert("\u{2060}", at: amount.index(after: amount.startIndex)) }
    return "\(plural) · \(amount) \(String(localized: "estimated", bundle: .module))"
  }

  /// What "Copy details" writes for the local fallback. Only `.localOnly` has a reason
  /// to copy: the other states already say what they mean in a sentence.
  static func copyableDetails(for mode: StorageMode) -> String? {
    if case .localOnly(let reason) = mode { return reason }
    return nil
  }

  /// What "Copy details" writes for an erase that cannot run: the reason the store
  /// was not opened.
  static func copyableDetails(for scope: EraseScope) -> String? {
    if case .unavailable(let reason) = scope { return reason }
    return nil
  }
}
