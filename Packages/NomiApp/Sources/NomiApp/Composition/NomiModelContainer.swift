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
  /// The app's schema, versioned (I-6). Its model list is `NomiSchemaV1.models`,
  /// the same list `NomiCore.InMemoryModelContainer.shared` reads, so a model
  /// cannot be present in one store and missing from the other.
  public static let schema = Schema(versionedSchema: NomiSchemaV1.self)

  /// The identifier in `App/Nomi.entitlements`. Named explicitly rather than
  /// left to `.automatic` so a mismatch between code and entitlement is a
  /// visible constant, not a silent fallback to a container nobody meant.
  public static let cloudKitContainerIdentifier = "iCloud.com.shivams07.nomi"

  public static func makeCloudKit() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      migrationPlan: NomiMigrationPlan.self,
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
      migrationPlan: NomiMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)]
    )
  }

  /// Local-only, at an explicit file. Tests use it to open a store they wrote
  /// themselves, and the recovery path uses it through the `local` parameter of
  /// `makeWithLocalFallback`.
  public static func makeLocal(at url: URL) throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      migrationPlan: NomiMigrationPlan.self,
      configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)]
    )
  }

  /// Where the local store lives by default. This is the path `makeLocal()`
  /// opens, so recovery moves the file the app would otherwise reopen.
  public static var defaultStoreURL: URL {
    ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
  }

  /// Scratch storage for the last-resort case. Used only when neither the
  /// CloudKit nor the local store could be opened, and nothing is kept.
  static func makeInMemory() throws -> ModelContainer {
    try ModelContainer(
      for: schema,
      configurations: [
        ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
      ]
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
  /// **A store that will not open is moved aside, not deleted (R7).** The local
  /// store is the only one that can be unopenable on disk; CloudKit failing
  /// alone moves nothing. When both fail, the file is moved into `Recovered/`
  /// with a timestamped name, a `StoreRecoveryNotice` is saved, and a fresh
  /// store is opened. If that also fails, the app runs on an in-memory store
  /// and says so. Only a failure to create even an in-memory store is fatal,
  /// and by then there is nothing left to run on.
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
    forceCloudKit: Bool = currentForceCloudKitRequested,
    local: () throws -> ModelContainer = makeLocal,
    storeURL: URL = defaultStoreURL,
    recoveryDefaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    now: () -> Date = Date.init
  ) -> (container: ModelContainer, mode: StorageMode) {
    do {
      return try openStore(
        cloudKit: cloudKit, isSimulatorDebugBuild: isSimulatorDebugBuild,
        forceCloudKit: forceCloudKit, local: local)
    } catch {
      // Only the type name is logged. The error text can carry a file path or a
      // store description, and this line must be safe to read in a sysdiagnose.
      logger.error(
        "Store could not be opened (\(String(describing: type(of: error)), privacy: .public)); moving it aside"
      )
    }

    // Recovery. Reaching here means CloudKit and the local store both failed,
    // so the file on disk is the suspect. Move it, do not delete it.
    let stamp = now()
    let moved: String?
    do {
      moved = try moveStoreAside(at: storeURL, stamp: stamp, fileManager: fileManager)
    } catch {
      logger.error(
        "Store could not be moved aside (\(String(describing: type(of: error)), privacy: .public))")
      return inMemoryFallback()
    }
    if let moved {
      StoreRecoveryRecord.save(
        StoreRecoveryNotice(movedAt: stamp, fileName: moved), to: recoveryDefaults)
      logger.notice("Moved an unopenable store aside to Recovered/")
    }

    do {
      return try openStore(
        cloudKit: cloudKit, isSimulatorDebugBuild: isSimulatorDebugBuild,
        forceCloudKit: forceCloudKit, local: local)
    } catch {
      logger.error(
        "Fresh store could not be opened (\(String(describing: type(of: error)), privacy: .public))")
      return inMemoryFallback()
    }
  }

  /// The open path without recovery. Throws only when the local store fails,
  /// because a CloudKit failure is answered by the local store here.
  private static func openStore(
    cloudKit: () throws -> ModelContainer,
    isSimulatorDebugBuild: Bool,
    forceCloudKit: Bool,
    local: () throws -> ModelContainer
  ) throws -> (container: ModelContainer, mode: StorageMode) {
    if let reason = simulatorLocalOnlyReason(
      isSimulatorDebugBuild: isSimulatorDebugBuild, forceCloudKit: forceCloudKit)
    {
      logger.notice("Opening local storage without CloudKit: \(reason, privacy: .public)")
      return (try local(), .localOnly(reason: reason))
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
      return (try local(), .localOnly(reason: String(describing: error)))
    }
  }

  /// The last resort: an in-memory store, so the app launches and nothing is
  /// kept. The reason is shown to the user in Settings.
  private static func inMemoryFallback() -> (container: ModelContainer, mode: StorageMode) {
    do {
      return (
        try makeInMemory(),
        .localOnly(
          reason:
            "Nomi could not open storage on this device, so nothing you add will be kept after you close the app."
        )
      )
    } catch {
      fatalError(
        "Nomi could not open any store, not even in memory (\(String(describing: type(of: error))))"
      )
    }
  }

  /// Moves the store, its `-shm` and `-wal` sidecars and its support directory
  /// into `Recovered/` beside it. Each name is stamped with the UTC time, so a
  /// second recovery never overwrites the first.
  ///
  /// Returns the main file's stamped name when the main store file itself was
  /// moved; that name is what a `StoreRecoveryNotice` records. Returns nil when
  /// the main file did not exist. An orphan `-wal`, `-shm` or support directory
  /// is still moved out of the way (it would be replayed into the next store),
  /// but it is not reported as a recovery and records nothing.
  static func moveStoreAside(
    at storeURL: URL, stamp: Date, fileManager: FileManager
  ) throws -> String? {
    let directory = storeURL.deletingLastPathComponent()
    let base = storeURL.deletingPathExtension().lastPathComponent
    let ext = storeURL.pathExtension
    let recovered = directory.appendingPathComponent("Recovered", isDirectory: true)
    let timestamp = recoveryStamp(stamp)

    var moves: [(from: URL, to: URL)] = []
    var mainExisted = false
    for suffix in ["", "-shm", "-wal"] {
      let from = directory.appendingPathComponent("\(base).\(ext)\(suffix)")
      if fileManager.fileExists(atPath: from.path) {
        if suffix.isEmpty { mainExisted = true }
        moves.append((from, recovered.appendingPathComponent("\(base)-\(timestamp).\(ext)\(suffix)")))
      }
    }
    // The support directory keeps the same stamp under a dotted name, so it
    // sits beside the stamped store files in Recovered/.
    let support = directory.appendingPathComponent(".\(base)_SUPPORT", isDirectory: true)
    if fileManager.fileExists(atPath: support.path) {
      moves.append(
        (support, recovered.appendingPathComponent(".\(base)-\(timestamp)_SUPPORT", isDirectory: true)))
    }
    guard !moves.isEmpty else { return nil }

    try fileManager.createDirectory(at: recovered, withIntermediateDirectories: true)
    for move in moves {
      try fileManager.moveItem(at: move.from, to: move.to)
    }
    return mainExisted ? "\(base)-\(timestamp).\(ext)" : nil
  }

  /// `yyyyMMdd'T'HHmmss` in UTC, for names in `Recovered/`.
  static func recoveryStamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
    return formatter.string(from: date)
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
