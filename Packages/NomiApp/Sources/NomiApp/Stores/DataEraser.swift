import Foundation
import NomiCore
import NomiIngest
import SwiftData

/// I-13 Amendment 1, B5. Erases everything the app holds, in the order below.
///
/// The gate is closed first and reopened on every exit, with the token that
/// closed it. A failure that leaves rows, defaults or a credential behind (a
/// delete, a store save, a reseed, a credential delete) is remembered and
/// reported last as `.incomplete`, so the rest of the erase still runs. Nothing
/// here is undone: the order is the safety property. Once a step is done it is
/// not done again by a later one.
@MainActor
final class DataEraser: DataErasing {
  private let container: ModelContainer
  private let storageModeProvider: @MainActor () -> StorageMode
  private let sync: AppSyncCoordinator
  private let pipeline: IngestPipeline
  private let mail: any MailConnectionService
  private let credentials: any MailCredentialStoring
  private let notifications: any BudgetNotificationScheduling
  private let preferences: any KeyValueStoring
  private let standardDefaults: UserDefaults
  private let firstRun: FirstRunGate
  private let writes: WriteCoordinator
  private let fileManager: FileManager
  private let storeDirectory: URL
  private let tempDirectory: URL
  private let disconnectTimeout: TimeInterval
  private let deleteRows: @MainActor (any PersistentModel.Type, ModelContext) throws -> Void
  private let saveStore: @MainActor (ModelContext) throws -> Void
  private let dropCaches: @MainActor () -> Void
  private let reopenGate: @MainActor (EraseToken) async -> Void

  /// `storageMode` is read at each call, so the scope a Settings row shows and the
  /// scope an erase acts on are the same answer.
  ///
  /// `disconnectTimeout`, `deleteRows`, `saveStore`, `dropCaches` and `reopenGate`
  /// exist for tests. Production takes the defaults: 10 s for the mail disconnect,
  /// a plain `delete(model:)` per model, a plain `save()`, the write coordinator's
  /// cache drop, and the sync coordinator's `endErase`.
  init(
    container: ModelContainer,
    storageMode: @escaping @MainActor () -> StorageMode,
    sync: AppSyncCoordinator,
    pipeline: IngestPipeline,
    mail: any MailConnectionService,
    credentials: any MailCredentialStoring,
    notifications: any BudgetNotificationScheduling,
    preferences: any KeyValueStoring,
    standardDefaults: UserDefaults = .standard,
    firstRun: FirstRunGate,
    writes: WriteCoordinator,
    fileManager: FileManager = .default,
    storeDirectory: URL = NomiModelContainer.defaultStoreURL.deletingLastPathComponent(),
    tempDirectory: URL = FileManager.default.temporaryDirectory,
    disconnectTimeout: TimeInterval = 10,
    deleteRows: @escaping @MainActor (any PersistentModel.Type, ModelContext) throws -> Void = { model, context in
      try context.delete(model: model)
    },
    saveStore: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
    dropCaches: (@MainActor () -> Void)? = nil,
    reopenGate: (@MainActor (EraseToken) async -> Void)? = nil
  ) {
    self.container = container
    self.storageModeProvider = storageMode
    self.sync = sync
    self.pipeline = pipeline
    self.mail = mail
    self.credentials = credentials
    self.notifications = notifications
    self.preferences = preferences
    self.standardDefaults = standardDefaults
    self.firstRun = firstRun
    self.writes = writes
    self.fileManager = fileManager
    self.storeDirectory = storeDirectory
    self.tempDirectory = tempDirectory
    self.disconnectTimeout = disconnectTimeout
    self.deleteRows = deleteRows
    self.saveStore = saveStore
    self.dropCaches = dropCaches ?? { writes.didWrite(affectedCategoryIDs: []) }
    self.reopenGate = reopenGate ?? { token in await sync.endErase(token) }
  }

  var scope: EraseScope {
    Self.scope(for: storageModeProvider())
  }

  /// `.cloudKit` reaches iCloud. A paused account and a local fallback store do
  /// not, and `.localOnly` and every paused reason are allowed to erase on this
  /// device (G9). `.inMemory` has no persistent store to erase.
  static func scope(for mode: StorageMode) -> EraseScope {
    switch mode {
    case .cloudKit:
      return .everywhere
    case .cloudKitPaused, .localOnly:
      return .thisDeviceOnly
    case .inMemory(let reason):
      return .unavailable(reason: reason)
    }
  }

  func eraseEverything() async throws {
    // a. Preflight. A launch that never opened the real store has nothing to reach.
    if case .unavailable(let reason) = scope {
      throw EraseError.unavailable(reason: reason)
    }

    // b. Close the gate. That covers the coordinator's own work and every mail sync or
    // backfill from any screen (`MailWorkGate`), and each one has returned by the time
    // this step is past. Work still running at the deadline means nothing was erased.
    let token: EraseToken
    do {
      token = try await sync.beginErase()
    } catch CoordinatorEraseError.busy {
      throw EraseError.busy
    }

    // From here the gate is closed. No step below throws, so the reopen in `k`
    // is reached on every path. A step that starts to throw must be caught here.
    var incomplete = false

    // c. Mail. Disconnect is best effort: it can wait on a socket that never
    // answers, so it is abandoned at the deadline. The credential is then
    // deleted directly, because the mailbox layer skips its own delete when
    // the disconnect throws. A credential that will not delete is not success:
    // the password is still on the device, so the erase reports incomplete
    // after every other step has run (Andrews' ruling, PR #217).
    await disconnectMailBestEffort()
    do {
      try credentials.delete()
    } catch {
      NomiLog.sync.error("erase could not delete the mail credential: \(NomiLog.describe(error), privacy: .public)")
      incomplete = true
    }

    // d. Store. Every row of every model, one save, inside the pipeline's
    // exclusive section. A batch queued behind this is refused by the epoch.
    let rowsDeleted = await pipeline.runExclusiveForErase {
      await MainActor.run { self.deleteEveryRow() }
    }
    if !rowsDeleted { incomplete = true }

    // e. Reseed at once, with the calls bootstrap makes (G8).
    if !reseedDefaults() { incomplete = true }

    // f. Budget alerts, pending and delivered (G3).
    await notifications.removeAllAlerts()

    // g. Files the store and the exports left beside themselves (G1, G2).
    removeErasedFiles()

    // h. Preferences: the fixed list, with the call for each kind, then the two
    // keys that live in UserDefaults.standard.
    for entry in PreferenceKey.erasable {
      switch entry.kind {
      case .bool:
        preferences.set(false, forKey: entry.key)
      case .data:
        preferences.set(nil as Data?, forKey: entry.key)
      }
    }
    for key in PreferenceKey.standardDefaultsErasable {
      standardDefaults.removeObject(forKey: key)
    }

    // i. Every cache drops. No observer runs: there are no budgets left to evaluate.
    dropCaches()

    // j. First run starts again from Welcome (G10).
    firstRun.restartAfterErase()

    // k. Reopen the gate. Only the holder's token can do this.
    await reopenGate(token)

    // l. Reported last, so every other step has already run. Covers a failed
    // credential delete, a failed store save and a failed reseed.
    if incomplete { throw EraseError.incomplete }
  }

  // MARK: - Steps

  /// Bounded by `disconnectTimeout`. The disconnect runs in its own task, and a
  /// timer resumes the caller if it does not return in time. The task is left to
  /// finish on its own, and nothing waits for it. Its late writes are not only the
  /// backfill flag. When the mailbox layer's disconnect returns, it removes the
  /// stored password and publishes `.disconnected`, but only while no connect has
  /// begun since that disconnect did (`IMAPMailConnectionService`). A mailbox
  /// connected after this erase keeps its password. The mail stack then clears the
  /// unfinished-backfill flag, but only if no backfill has started since
  /// (`CursorPersistingMailConnectionService`). Both guards are tested in
  /// `IMAPMailDisconnectRaceTests` and `MailDisconnectMarkerTests`.
  private func disconnectMailBestEffort() async {
    let service = mail
    let nanoseconds = UInt64(max(0, disconnectTimeout) * 1_000_000_000)
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = SingleResume()
      let timer = Task {
        do {
          try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
          // Cancelled because the disconnect returned first. It must not resume the caller.
          return
        }
        if once.claim() { continuation.resume() }
      }
      Task {
        _ = try? await service.disconnect()
        timer.cancel()
        if once.claim() { continuation.resume() }
      }
    }
  }

  /// Deletes every row of every model in `NomiSchemaV1.models` and saves once.
  /// Returns `false` if a delete or the save threw.
  ///
  /// A delete that throws part-way stops the loop, and nothing here saves what
  /// came before it. Those deletes stay pending in the context, and the reseed's
  /// own save (inside `DefaultCategorySeed.apply`) commits them. So the models
  /// before the failure end up empty and the rest keep their rows until a retry.
  /// A failed save here can be committed by that same later save. Both cases are
  /// reported as `.incomplete`.
  private func deleteEveryRow() -> Bool {
    let context = container.mainContext
    do {
      for model in NomiSchemaV1.models {
        try deleteRows(model, context)
      }
      try saveStore(context)
      return true
    } catch {
      NomiLog.store.error("erase could not delete and save every row: \(NomiLog.describe(error), privacy: .public)")
      return false
    }
  }

  /// The same two calls `AppEnvironment.bootstrap` makes, then one save. Returns
  /// `false` on any failure.
  ///
  /// Each seed call saves on its own when it inserts something, so by the time
  /// the save here runs, the seeds are normally already on disk. A failure here
  /// is reported even though the seeds may be present. A failure inside a seed
  /// call is the case where they are missing. Either way a retry restores them,
  /// and so does the next launch, because bootstrap runs the same calls.
  private func reseedDefaults() -> Bool {
    let context = container.mainContext
    do {
      try DefaultCategorySeed.apply(in: context)
      try DefaultRuleSeed.apply(in: context)
      try saveStore(context)
      return true
    } catch {
      NomiLog.store.error("erase could not reseed defaults: \(NomiLog.describe(error), privacy: .public)")
      return false
    }
  }

  /// `Recovered/` beside the store, and the integrity-probe and CSV leftovers in
  /// the temporary directory. Matched by name only, so nothing else there is touched.
  /// A file that cannot be removed is logged, and the erase goes on.
  private func removeErasedFiles() {
    let recovered = storeDirectory.appendingPathComponent("Recovered", isDirectory: true)
    if fileManager.fileExists(atPath: recovered.path) {
      remove(recovered, what: "recovered-store folder")
    }
    let names = (try? fileManager.contentsOfDirectory(atPath: tempDirectory.path)) ?? []
    for name in names where Self.isErasableTemporaryName(name) {
      remove(tempDirectory.appendingPathComponent(name), what: "temporary file")
    }
  }

  /// `nomi-store-probe-*` and `nomi-report-*.csv`. Only the prefix and the suffix are matched.
  static func isErasableTemporaryName(_ name: String) -> Bool {
    if name.hasPrefix("nomi-store-probe-") { return true }
    return name.hasPrefix("nomi-report-") && name.hasSuffix(".csv")
  }

  private func remove(_ url: URL, what: String) {
    do {
      try fileManager.removeItem(at: url)
    } catch {
      NomiLog.store.error("erase could not remove a \(what, privacy: .public): \(NomiLog.describe(error), privacy: .public)")
    }
  }
}

/// Resumes a continuation exactly once, from either of two racing tasks.
private final class SingleResume: @unchecked Sendable {
  private let lock = NSLock()
  private var claimed = false

  /// True for the first caller only.
  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    if claimed { return false }
    claimed = true
    return true
  }
}
