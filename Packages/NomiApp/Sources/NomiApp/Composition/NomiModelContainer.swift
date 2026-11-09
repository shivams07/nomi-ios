import Foundation
import NomiCore
import OSLog
import SwiftData

/// The real store: SwiftData over the **CloudKit private database**.
///
/// Two things about the models make this work, and both were decided in U1
/// rather than here: every property carries a default value, and no uniqueness
/// constraint is declared anywhere. CloudKit requires the first and forbids the
/// second — which is also the root of R5 (two devices can create duplicate rows
/// that only `IngestPipeline.reconcile()` can collapse) and of R16 (duplicate
/// budget notifications). Those are accepted costs, not oversights.
public enum NomiModelContainer {
  /// Matches `NomiCore.InMemoryModelContainer.shared` exactly. A model missing
  /// from one and present in the other is a store that opens in the app and
  /// traps in a preview, or the reverse.
  public static let schema = Schema([
    Transaction.self,
    NomiCore.Category.self,
    Budget.self,
    BudgetAlertLog.self,
    Rule.self,
    Account.self,
    AccountBinding.self,
    ColumnMappingRecord.self,
  ])

  /// The identifier in `App/Nomi.entitlements`. Named explicitly rather than
  /// left to `.automatic` so a mismatch between code and entitlement is a
  /// visible constant, not a silent fallback to a container nobody meant.
  public static let cloudKitContainerIdentifier = "iCloud.com.shivams07.nomi"

  public static func makeCloudKit() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(
          schema: schema,
          cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
      ]
    )
  }

  /// Local-only, same schema. Not a test double: it is what the app runs on
  /// when CloudKit is genuinely unavailable.
  public static func makeLocal() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
    )
  }

  /// What the app actually calls.
  ///
  /// **The fallback is the point.** Constructing a CloudKit-backed container
  /// can fail outright — a corrupt store, a schema CloudKit rejects. Letting
  /// that `try` propagate turns "sync is unavailable" into "the app does not
  /// launch", and launching is the acceptance criterion this unit is measured
  /// on.
  ///
  /// Falling back loses sync, not data: the schema is identical, so a later
  /// launch that does reach CloudKit reads the same local store and begins
  /// syncing it.
  ///
  /// Only the second failure is fatal, and by then there is nothing to run on.
  ///
  /// **Returns the mode as well as the container (B11).** It used to `print`
  /// and return only the container, so the one person who could see that the
  /// app had silently stopped syncing was whoever had Xcode attached. The
  /// caller now carries the answer as far as Settings.
  ///
  /// ⚠️ **A missing iCloud entitlement is not one of the failures this
  /// catches, and B11 originally assumed it was.** CI proved otherwise: on a
  /// runner with no entitlement `makeCloudKit()` returns normally, and the
  /// mirroring delegate then fails asynchronously (it got as far as
  /// "Successfully enqueued setup request" before trapping the process).
  ///
  /// U9b resolved this, and split it in two along the way. A missing
  /// entitlement is a build error, not a runtime state, and is not detectable
  /// at runtime at all — so it is guarded at CI time by
  /// `EntitlementsParityTests`. An *entitled* build with no usable iCloud
  /// account is the state users actually reach, and `StorageModeMonitor`
  /// reports it as `.cloudKitPaused` without touching the store. So what this
  /// function returns is still only the *construction* answer; it is no longer
  /// the whole answer, and it is no longer what Settings renders on its own.
  ///
  /// **Simulator Debug builds never reach CloudKit by default (SIM1).** An
  /// unsigned simulator build has no iCloud entitlement, and that case does
  /// not throw: `makeCloudKit()` returns, and the mirroring delegate traps the
  /// process asynchronously a moment later (CrashReporter: `EXC_BREAKPOINT` in
  /// `NSCloudKitMirroringDelegate _performSetupRequest:`). So the decision is
  /// made before the CloudKit maker is called at all. See
  /// `simulatorLocalOnlyReason`. Setting `NOMI_FORCE_CLOUDKIT=1` restores
  /// CloudKit for a signed simulator build; it has no effect on a device or a
  /// Release build.
  ///
  /// - Parameters:
  ///   - cloudKit: the CloudKit container maker. Injectable **only** so the
  ///     fallback branch is reachable in a test — constructing a real CloudKit
  ///     container under `swift test` traps the process, so a test that called
  ///     the default would take the whole suite down with it. Production passes
  ///     nothing and gets `makeCloudKit`.
  ///   - isSimulatorDebugBuild: production passes nothing. Injectable so the
  ///     simulator branch is testable from a macOS `swift test`.
  ///   - forceCloudKit: production passes nothing. Injectable for the same
  ///     reason as `isSimulatorDebugBuild`.
  public static func makeWithLocalFallback(
    cloudKit: () throws -> ModelContainer = makeCloudKit,
    isSimulatorDebugBuild: Bool = currentBuildIsSimulatorDebug,
    forceCloudKit: Bool = currentForceCloudKitRequested
  ) -> (container: ModelContainer, mode: StorageMode) {
    if let reason = simulatorLocalOnlyReason(
      isSimulatorDebugBuild: isSimulatorDebugBuild, forceCloudKit: forceCloudKit)
    {
      logger.notice("Opening local storage without CloudKit: \(reason, privacy: .public)")
      return (try! makeLocal(), .localOnly(reason: reason))
    }
    do {
      return (try cloudKit(), .cloudKit)
    } catch {
      // `Logger`, not `print`: a `print` is invisible in a release build and in
      // any sysdiagnose the user could send. This line is the first thing to
      // look for when "my other device does not see my transactions" is
      // reported, so it has to survive leaving the debugger.
      logger.error(
        "CloudKit container unavailable, falling back to local storage: \(error, privacy: .public)")
      return (try! makeLocal(), .localOnly(reason: String(describing: error)))
    }
  }

  /// The SIM1 decision, pure so it can be tested without a CloudKit container.
  ///
  /// Returns the reason to open the local store without trying CloudKit, or
  /// `nil` to keep the CloudKit path exactly as before. The local store is
  /// chosen only when both hold: this is a simulator Debug build, and
  /// `NOMI_FORCE_CLOUDKIT` is not set. Device and Release builds always get
  /// `nil`, because the two inputs are compile-time constants there.
  ///
  /// The entitlement itself is not checked. Detecting it at runtime needs
  /// private API, and the build-time guard (`EntitlementsParityTests`) already
  /// covers the signed case. So a signed simulator Debug build also opens the
  /// local store unless `NOMI_FORCE_CLOUDKIT=1` is set.
  public static func simulatorLocalOnlyReason(
    isSimulatorDebugBuild: Bool,
    forceCloudKit: Bool
  ) -> String? {
    guard isSimulatorDebugBuild, !forceCloudKit else { return nil }
    return "Simulator build without iCloud entitlement"
  }

  /// True only in a simulator Debug build. Under any other compile
  /// configuration this is a constant `false`, so device and Release code
  /// never reads the environment.
  public static let currentBuildIsSimulatorDebug: Bool = {
    #if DEBUG && targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }()

  /// The escape hatch, read from `environment`. The compile guard is here, not
  /// only at the call site: outside a simulator Debug build the variable is
  /// never honoured, whatever the environment holds. Launch a simulator build
  /// with CloudKit with `SIMCTL_CHILD_NOMI_FORCE_CLOUDKIT=1 xcrun simctl launch …`,
  /// or set the variable in the Xcode scheme.
  public static func forceCloudKitRequested(in environment: [String: String]) -> Bool {
    #if DEBUG && targetEnvironment(simulator)
      return environment["NOMI_FORCE_CLOUDKIT"] == "1"
    #else
      _ = environment
      return false
    #endif
  }

  /// The production value: the process environment, through the guarded reader.
  /// Computed rather than stored so it reads the environment at the moment it
  /// is asked, which is what lets a test set the variable and see the result.
  public static var currentForceCloudKitRequested: Bool {
    forceCloudKitRequested(in: ProcessInfo.processInfo.environment)
  }

  private static let logger = Logger(subsystem: "com.shivams07.nomi", category: "storage")
}
