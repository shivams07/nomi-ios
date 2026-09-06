import Foundation

/// Which store the app is actually running on.
///
/// The CloudKit container can fail to construct — a corrupt store, a schema
/// CloudKit rejects. The app falls back to a local-only store and keeps
/// running, which is right: losing sync is not a reason to refuse to launch.
///
/// Note what this does **not** cover. A missing iCloud entitlement does not
/// make the container throw; it constructs, and mirroring fails afterwards
/// (see `NomiModelContainer.makeWithLocalFallback`). Such a build reports
/// `.cloudKit` here and shows "On" while nothing syncs. Closing that gap needs
/// an account check, not a `catch`.
///
/// **What was wrong is that it said so only to the Xcode console.** A user in
/// that state sees an app that works perfectly and simply never appears on
/// their other device, with nothing anywhere to explain it. That reads as data
/// loss and it is the hardest kind of report to act on, because the person
/// reporting it has nothing to report.
///
/// In NomiCore rather than NomiApp because `SettingsScreen` (NomiUI) renders
/// it, and NomiUI cannot see NomiApp.
public enum StorageMode: Sendable, Equatable {
  case cloudKit
  /// `reason` is the underlying error, already stringified. Shown to the user
  /// as a caption: it is developer-shaped text, but a developer-shaped
  /// explanation the user can read out beats no explanation at all.
  case localOnly(reason: String)

  public var isSyncing: Bool {
    if case .cloudKit = self { return true }
    return false
  }

  public var reason: String? {
    if case .localOnly(let reason) = self { return reason }
    return nil
  }
}
