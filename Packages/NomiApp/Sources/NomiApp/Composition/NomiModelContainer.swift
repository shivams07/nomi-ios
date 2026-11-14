import Foundation
import NomiCore
import OSLog
import SQLite3
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

  /// Shown when the store could not be opened this launch and was **not**
  /// moved. The next launch tries the real store again (I-6 Amendment 1).
  public static let retryLaterReason =
    "Nomi could not open your saved data this time, so nothing you add will be kept after you close the app. Close Nomi and open it again."

  /// Shown when even a fresh or in-memory store could not be used after a
  /// recovery attempt. The original file is either moved aside or left in place.
  static let storageUnavailableReason =
    "Nomi could not open storage on this device, so nothing you add will be kept after you close the app."

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

  /// Scratch storage for the last-resort case. Used only when the store could
  /// not be opened and nothing is kept.
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
  /// **A store is moved aside only on positive evidence that it is corrupt
  /// (R7, I-6 Amendment 1).** When both opens fail, `classifyUnopenableStore`
  /// decides. Only `.corrupt` moves the file into `Recovered/`, saves a
  /// `StoreRecoveryNotice` and reopens a fresh store. Every other failure (a
  /// locked device, a missing file, a copy that cannot be made, a store that
  /// passes its integrity check, a migration or model mismatch) is
  /// `.retryLater`: nothing under the store's directory is touched, the app
  /// runs on an in-memory store with `persistent == false`, and the next launch
  /// tries the real store again.
  ///
  /// **Returns the mode as well as the container (B11).** It used to `print`
  /// and return only the container, so the one person who could see that the
  /// app had silently stopped syncing was whoever had Xcode attached. The
  /// caller now carries the answer as far as Settings.
  ///
  /// `persistent` is `true` only when the container writes to the on-disk
  /// store. `false` means nothing this launch writes will survive it, so the
  /// caller must not run background or foreground sync, and must not write
  /// preferences to `UserDefaults` (see `AppServices`).
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
  ///   - scratchDirectory: where the integrity probe copies the store. Production
  ///     passes nothing; a test points it at a directory it can make unwritable.
  public static func makeWithLocalFallback(
    cloudKit: () throws -> ModelContainer = makeCloudKit,
    isSimulatorDebugBuild: Bool = currentBuildIsSimulatorDebug,
    forceCloudKit: Bool = currentForceCloudKitRequested,
    local: () throws -> ModelContainer = makeLocal,
    storeURL: URL = defaultStoreURL,
    recoveryDefaults: UserDefaults = .standard,
    fileManager: FileManager = .default,
    scratchDirectory: URL = FileManager.default.temporaryDirectory,
    now: () -> Date = Date.init
  ) -> (container: ModelContainer, mode: StorageMode, persistent: Bool) {
    do {
      let opened = try openStore(
        cloudKit: cloudKit, isSimulatorDebugBuild: isSimulatorDebugBuild,
        forceCloudKit: forceCloudKit, local: local)
      return (opened.container, opened.mode, true)
    } catch {
      // Falls through to classification. The error itself is not logged: its
      // text can carry a path, and the verdict below says what matters.
    }

    let verdict = classifyUnopenableStore(
      at: storeURL, fileManager: fileManager, scratchDirectory: scratchDirectory)
    logger.error("Store could not be opened: \(verdictName(verdict), privacy: .public)")

    // Anything other than positive evidence of corruption leaves the file alone.
    // Nothing is moved, written or created here, and no notice is saved.
    if case .retryLater = verdict {
      return inMemoryFallback(reason: retryLaterReason)
    }

    let stamp = now()
    let moved: String?
    do {
      moved = try moveStoreAside(at: storeURL, stamp: stamp, fileManager: fileManager)
    } catch {
      // The original stays where it is, byte for byte. Nothing is deleted.
      logger.error(
        "Store could not be moved aside (\(String(describing: type(of: error)), privacy: .public))")
      return inMemoryFallback()
    }
    if let moved {
      StoreRecoveryRecord.save(
        StoreRecoveryNotice(movedAt: stamp, fileName: moved), to: recoveryDefaults)
      logger.notice("Moved a corrupt store aside to Recovered/")
    }

    do {
      let opened = try openStore(
        cloudKit: cloudKit, isSimulatorDebugBuild: isSimulatorDebugBuild,
        forceCloudKit: forceCloudKit, local: local)
      return (opened.container, opened.mode, true)
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
  /// kept. The reason is shown to the user in Settings. Never persistent.
  private static func inMemoryFallback(
    reason: String = storageUnavailableReason
  ) -> (container: ModelContainer, mode: StorageMode, persistent: Bool) {
    do {
      return (try makeInMemory(), .localOnly(reason: reason), false)
    } catch {
      fatalError(
        "Nomi could not open any store, not even in memory (\(String(describing: type(of: error))))"
      )
    }
  }

  // MARK: - Classification (I-6 Amendment 1)

  /// What the app concluded about a store file that would not open.
  public enum StoreFailureVerdict: Equatable, Sendable {
    /// The only verdict that moves a file.
    case corrupt(CorruptionEvidence)
    /// Nothing moved, nothing written; in-memory for this launch.
    case retryLater(RetryReason)
  }

  public enum CorruptionEvidence: String, Sendable {
    /// A non-empty main file whose first 16 bytes are not `SQLite format 3\0`.
    case notSQLiteHeader
    /// A copy of the file fails `PRAGMA quick_check`, or SQLite reports
    /// corruption (11) or not-a-database (26) while opening or checking it.
    case integrityCheckFailed
  }

  public enum RetryReason: String, Sendable {
    case noStoreFile
    /// The file exists but cannot be read. Before first unlock, `open(2)` fails
    /// with EPERM; a mode-bits denial fails with EACCES. Both land here.
    case unreadable
    case emptyFile
    /// The integrity probe could not copy the file, for example a full disk or
    /// an unwritable scratch directory.
    case probeCopyFailed
    case sqliteOpenFailed
    /// The copy passes `PRAGMA quick_check(1)`. The store is not corrupt, so it
    /// is not moved; a model mismatch or failed migration lands here too.
    case storeIntact
    /// SQLite reported busy, locked, I/O error or similar; the answer is unknown.
    case integrityCheckInconclusive
  }

  /// SQLite's result codes used here, masked to the primary code.
  private static let sqlitePrimaryCorrupt: Int32 = 11
  private static let sqlitePrimaryNotADatabase: Int32 = 26
  private static let sqlitePrimaryOK: Int32 = 0
  private static let sqliteRow: Int32 = 100

  /// The first 16 bytes of every SQLite database file.
  private static let sqliteHeader = Array("SQLite format 3\u{0}".utf8)

  /// Decides whether a store file that would not open is corrupt. Rules run in
  /// order and the first that applies is the verdict. Only `.corrupt` may lead
  /// to a move.
  ///
  /// The open's own error cannot be classified: a SwiftData failure bridges to
  /// one generic error for a corrupt file, an unreadable one and an uncreatable
  /// one alike (measured, I-6 Amendment 1). So the file itself is examined.
  ///
  /// The integrity check runs on a copy, never on the store, so a probe leaves
  /// the store byte-identical.
  public static func classifyUnopenableStore(
    at storeURL: URL,
    fileManager: FileManager = .default,
    scratchDirectory: URL = FileManager.default.temporaryDirectory
  ) -> StoreFailureVerdict {
    // 1. Nothing on disk to classify.
    guard fileManager.fileExists(atPath: storeURL.path) else {
      return .retryLater(.noStoreFile)
    }

    // 2. Readability. Before first unlock the file can be stat'ed but cannot be
    //    opened. The handle is closed on every path.
    let header: [UInt8]
    do {
      let handle = try FileHandle(forReadingFrom: storeURL)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: 16) ?? Data()
      header = Array(data)
    } catch {
      return .retryLater(.unreadable)
    }

    // 3. An empty file is not a database, but there is nothing to recover either.
    if header.isEmpty {
      return .retryLater(.emptyFile)
    }

    // 4. Positive evidence of corruption, from the bytes alone: a short file, or
    //    a non-empty file that does not start with the SQLite header.
    if header != sqliteHeader {
      return .corrupt(.notSQLiteHeader)
    }

    // 5. Copy the main file and its WAL into a probe directory. `-shm` is not
    //    copied; SQLite rebuilds it.
    let probe = scratchDirectory.appendingPathComponent(
      "nomi-store-probe-\(UUID().uuidString)", isDirectory: true)
    let storeName = storeURL.lastPathComponent
    let walName = storeName + "-wal"
    let walURL = storeURL.deletingLastPathComponent().appendingPathComponent(walName)

    // Every path after this point removes the probe directory.
    defer {
      try? fileManager.removeItem(at: probe)
    }

    do {
      try fileManager.createDirectory(at: probe, withIntermediateDirectories: false)
      try fileManager.copyItem(at: storeURL, to: probe.appendingPathComponent(storeName))
      if fileManager.fileExists(atPath: walURL.path) {
        try fileManager.copyItem(at: walURL, to: probe.appendingPathComponent(walName))
      }
    } catch {
      return .retryLater(.probeCopyFailed)
    }
    // 6 and 7 run on the copy, in `integrityProbe`.
    return integrityProbe(of: probe.appendingPathComponent(storeName))
  }

  /// Rules 6 and 7 of `classifyUnopenableStore`, on a file the caller has
  /// already copied. Internal so a test can point it at a file it has made
  /// unopenable or locked. The file is opened without CREATE, so a missing
  /// file is never turned into an empty database.
  static func integrityProbe(of copy: URL) -> StoreFailureVerdict {
    var db: OpaquePointer?
    var stmt: OpaquePointer?
    defer {
      sqlite3_finalize(stmt)
      sqlite3_close_v2(db)
    }

    // 6. Open the copy. No CREATE.
    let openCode = sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE, nil) & 0xFF
    if openCode == sqlitePrimaryCorrupt || openCode == sqlitePrimaryNotADatabase {
      return .corrupt(.integrityCheckFailed)
    }
    if openCode != sqlitePrimaryOK {
      return .retryLater(.sqliteOpenFailed)
    }

    // 7. Integrity check on the copy.
    let prepareCode = sqlite3_prepare_v2(db, "PRAGMA quick_check(1)", -1, &stmt, nil) & 0xFF
    if prepareCode == sqlitePrimaryCorrupt || prepareCode == sqlitePrimaryNotADatabase {
      return .corrupt(.integrityCheckFailed)
    }
    if prepareCode != sqlitePrimaryOK {
      return .retryLater(.integrityCheckInconclusive)
    }

    let stepCode = sqlite3_step(stmt) & 0xFF
    if stepCode == sqlitePrimaryCorrupt || stepCode == sqlitePrimaryNotADatabase {
      return .corrupt(.integrityCheckFailed)
    }
    guard stepCode == sqliteRow else {
      return .retryLater(.integrityCheckInconclusive)
    }
    guard let raw = sqlite3_column_text(stmt, 0) else {
      return .corrupt(.integrityCheckFailed)
    }
    let result = String(cString: UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self))
    return result == "ok" ? .retryLater(.storeIntact) : .corrupt(.integrityCheckFailed)
  }

  /// The name logged for a verdict. It carries no path and no error text.
  static func verdictName(_ verdict: StoreFailureVerdict) -> String {
    switch verdict {
    case .corrupt(let evidence): return "corrupt.\(evidence.rawValue)"
    case .retryLater(let reason): return "retryLater.\(reason.rawValue)"
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
  /// but it is not reported as a recovery and records nothing. This branch is
  /// tested directly. `makeWithLocalFallback` never reaches it with a missing
  /// main file, because `classifyUnopenableStore` returns `.noStoreFile` first.
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
