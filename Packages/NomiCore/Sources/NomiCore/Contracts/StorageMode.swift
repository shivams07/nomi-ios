import Foundation

/// Which store the app is running on, and whether it is actually syncing.
///
/// Three states, because two conditions were conflated in B11 and they need
/// different answers (U9b).
///
/// **The container failed to construct** — a corrupt store, a schema CloudKit
/// rejects. The app falls back to a local-only store and keeps running, which
/// is right: losing sync is not a reason to refuse to launch. That is
/// `.localOnly`, and regaining sync needs a relaunch.
///
/// **The container constructed but there is no usable iCloud account** —
/// signed out, restricted by Screen Time or a management profile, temporarily
/// unavailable. That is `.cloudKitPaused`. The store is still the CloudKit
/// one and is still the right store: it runs locally while no account is
/// present and the mirroring delegate resumes on its own when one appears, so
/// nothing needs to be swapped and no relaunch is needed.
///
/// **What was wrong is that the app said none of this.** A user in either
/// state sees an app that works perfectly and simply never appears on their
/// other device, with nothing anywhere to explain it. That reads as data loss
/// and it is the hardest kind of report to act on, because the person
/// reporting it has nothing to report.
///
/// A third condition is deliberately absent: a build with **no iCloud
/// entitlement**. It is not representable here because it is not detectable
/// here — constructing a `CKContainer` in such a process raises an uncatchable
/// ObjC exception rather than returning a status (it is what killed CI run
/// 33994342474). It is a build error, never a shipped state, and it is guarded
/// at CI time by `EntitlementsParityTests` instead.
///
/// In NomiCore rather than NomiApp because `SettingsScreen` (NomiUI) renders
/// it, and NomiUI cannot see NomiApp.
public enum StorageMode: Sendable, Equatable {
  /// The CloudKit store, with an available account. The only syncing state.
  case cloudKit
  /// The CloudKit store, with no usable account. Resumes when one appears —
  /// no relaunch, no store swap.
  case cloudKitPaused(SyncPauseReason)
  /// The local fallback store. `reason` is the underlying construction error,
  /// already stringified. Shown to the user as a caption: it is
  /// developer-shaped text, but a developer-shaped explanation the user can
  /// read out beats no explanation at all.
  case localOnly(reason: String)

  /// True for `.cloudKit` only. A paused container is not syncing, and saying
  /// otherwise is the exact false reassurance this type exists to remove.
  public var isSyncing: Bool {
    if case .cloudKit = self { return true }
    return false
  }

  /// The *construction* error, so `.localOnly` only. A paused account is not
  /// an error and has no error text — its explanation is chosen from
  /// `SyncPauseReason` at the display layer, where it can be written for a
  /// user rather than for a log.
  public var reason: String? {
    if case .localOnly(let reason) = self { return reason }
    return nil
  }
}

/// Why a CloudKit-backed store is not syncing despite having constructed.
///
/// Mirrors the `CKAccountStatus` cases the app can act on, but is a plain enum
/// declared here: **NomiCore must not depend on CloudKit at all.** The
/// translation lives in `CKAccountProbe` (NomiApp), which is the only file in
/// the repo that imports that framework.
public enum SyncPauseReason: Sendable, Equatable {
  /// No iCloud account is signed in on the device.
  case noAccount
  /// iCloud is restricted — Screen Time, or a management profile.
  case restricted
  /// iCloud is reachable but not usable right now. Expected to resolve on its
  /// own, which is why its display text is the only one that does not say
  /// "Off".
  case temporarilyUnavailable
  /// The status query itself failed. Carries the error text for the same
  /// reason `.localOnly` does: a user who can read it out gives a usable
  /// report.
  case couldNotDetermine(String)
}
