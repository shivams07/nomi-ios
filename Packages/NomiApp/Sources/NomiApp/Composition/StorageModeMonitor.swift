import CloudKit
import Combine
import Foundation
import NomiCore

/// The iCloud account probe (U9b).
///
/// A protocol rather than a direct `CKContainer` call so that **no test ever
/// constructs a `CKContainer`**. That is not tidiness: in a process without the
/// iCloud entitlement, constructing one raises an uncatchable ObjC exception
/// that takes the whole test process down. CI run 33994342474 is what that
/// looks like — a `swift test` binary dying with signal 5 and no failing
/// assertion to point at. `CKAccountProbe` is the production default and every
/// test injects a fake.
public protocol CloudKitAccountProbing: Sendable {
  /// `nil` means the account is available and sync can proceed.
  func pauseReason() async -> SyncPauseReason?
  /// Emits once per `.CKAccountChanged`. The values carry nothing — the
  /// notification is only a cue to re-probe, since it does not say what the
  /// status became.
  func accountChanges() -> AsyncStream<Void>
}

/// The real probe. **The only `import CloudKit` in the repo**, deliberately:
/// one file to audit when asking what the app does with CloudKit directly.
public struct CKAccountProbe: CloudKitAccountProbing {
  private let containerIdentifier: String

  public init(containerIdentifier: String = NomiModelContainer.cloudKitContainerIdentifier) {
    self.containerIdentifier = containerIdentifier
  }

  public func pauseReason() async -> SyncPauseReason? {
    do {
      let status = try await CKContainer(identifier: containerIdentifier).accountStatus()
      switch status {
      case .available: return nil
      case .noAccount: return .noAccount
      case .restricted: return .restricted
      case .temporarilyUnavailable: return .temporarilyUnavailable
      case .couldNotDetermine: return .couldNotDetermine("iCloud did not report a status.")
      @unknown default:
        // A status this build does not know is not the same as "syncing".
        // Reporting it as paused is the safe direction: the row says sync is
        // off when it might be on, rather than on when it is off.
        return .couldNotDetermine("Unrecognized iCloud account status (\(status.rawValue)).")
      }
    } catch {
      return .couldNotDetermine(String(describing: error))
    }
  }

  public func accountChanges() -> AsyncStream<Void> {
    let notifications = NotificationCenter.default.notifications(
      named: .CKAccountChanged
    )
    return AsyncStream { continuation in
      let task = Task {
        for await _ in notifications {
          continuation.yield(())
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

/// Combines what the container construction reported with what the account
/// probe says. Pure and free of both CloudKit and the main actor, so the
/// decision can be tested directly rather than through the monitor's
/// observation machinery.
public enum StorageModeResolver {
  /// - Parameters:
  ///   - constructed: what `makeWithLocalFallback` reported at launch.
  ///   - account: the probe's answer; `nil` means available.
  public static func resolve(constructed: StorageMode, account: SyncPauseReason?) -> StorageMode {
    switch constructed {
    case .localOnly:
      // The account is irrelevant here and must not override: this process is
      // not on a CloudKit store at all, so no account status can make it sync.
      // Saying "paused" would imply it resumes on its own, and it does not —
      // it needs a relaunch.
      return constructed
    case .cloudKit, .cloudKitPaused:
      guard let account else { return .cloudKit }
      return .cloudKitPaused(account)
    }
  }
}

/// Keeps `StorageMode` current for as long as the app is running.
///
/// B11 (#61) made the mode a construction-time constant, which was right for
/// the failure it modelled — a container that would not construct never
/// constructs later either — and wrong for the one users actually hit. Signing
/// out of iCloud does not fail any construction; it stops sync on a process
/// that is already running and has already reported "On".
///
/// So the mode is observed state. `AppEnvironment` republishes `$mode`, and
/// because `RootView` reads `environment.storageMode` in its `body`, the
/// Settings row re-renders on its own — no screen had to change.
@MainActor
public final class StorageModeMonitor: ObservableObject {
  @Published public private(set) var mode: StorageMode

  private let constructed: StorageMode
  private let probe: any CloudKitAccountProbing

  public init(constructed: StorageMode, probe: any CloudKitAccountProbing) {
    self.constructed = constructed
    self.probe = probe
    // Starts at the constructed value rather than at `.cloudKit`: a launch that
    // already fell back must not show "On" for the moment before the first
    // probe returns.
    self.mode = constructed
  }

  /// Probe once, then re-probe on every account change, for the lifetime of
  /// the task. Held by a `.task` on `RootContainerView`, so it is cancelled
  /// with the view.
  public func run() async {
    await refresh()
    for await _ in probe.accountChanges() {
      await refresh()
    }
  }

  /// One probe. Called by `run()` and again on every foreground — an account
  /// signed in while the app was backgrounded may not deliver a notification
  /// this process saw.
  public func refresh() async {
    let resolved = StorageModeResolver.resolve(
      constructed: constructed, account: await probe.pauseReason())
    // Assigning unconditionally would publish on every foreground and every
    // notification, re-rendering the tree for an answer that has not changed.
    guard resolved != mode else { return }
    mode = resolved
  }
}
