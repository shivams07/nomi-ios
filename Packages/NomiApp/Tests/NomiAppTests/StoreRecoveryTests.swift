import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// The recovery path of `makeWithLocalFallback` (R7, I-6 and I-6 Amendment 1).
/// A store is moved aside only on positive evidence that it is corrupt. Every
/// other failure leaves the file alone and runs in memory until the next launch.
///
/// XCTest, and every container is held to the end of its test with
/// `withExtendedLifetime`. The default maker is never used, so no CloudKit
/// container is built under `swift test` (see `NomiAppModuleTests`).
final class StoreRecoveryTests: XCTestCase {
  private struct CloudKitDown: Error {}
  private struct LocalDown: Error {}

  /// 2026-11-14T09:30:12Z. The stamp in every recovered name is `20261114T093012`.
  private let fixedNow = Date(timeIntervalSince1970: 1_794_648_612)
  private let fixedStamp = "20261114T093012"

  private let noRowsKeptReason =
    "Nomi could not open storage on this device, so nothing you add will be kept after you close the app."

  private var directory: URL!
  private var suiteName: String!
  private var defaults: UserDefaults!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    suiteName = UUID().uuidString
    defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
  }

  override func tearDownWithError() throws {
    defaults.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }

  private var storeURL: URL {
    directory.appendingPathComponent("default.store")
  }

  private var recoveredDirectory: URL {
    directory.appendingPathComponent("Recovered", isDirectory: true)
  }

  /// A valid V1 store with one row, written and closed.
  private func writeValidStore() throws {
    let container = try NomiModelContainer.makeLocal(at: storeURL)
    let context = ModelContext(container)
    context.insert(Rule(pattern: "SWIGGY*", categoryID: UUID()))
    try context.save()
    withExtendedLifetime(container) {}
  }

  /// **The recovery proof.** A 4 KB file of zeros at the store's path has a
  /// non-SQLite header, so it is positive evidence of corruption. The app must
  /// move it aside rather than delete it, record the move, open a fresh empty
  /// store, and launch as persistent.
  func testAnUnopenableStoreIsMovedAsideAndAFreshOneOpens() throws {
    let url = storeURL
    let corrupt = Data(repeating: 0, count: 4096)
    try corrupt.write(to: url)

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { try NomiModelContainer.makeLocal(at: url) },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    guard case .localOnly = result.mode else {
      return XCTFail("expected the local fallback after recovery, got \(result.mode)")
    }
    XCTAssertTrue(result.persistent, "a reopened store writes to disk")

    let moved = recoveredDirectory.appendingPathComponent("default-\(fixedStamp).store")
    let movedData = try Data(contentsOf: moved)
    XCTAssertEqual(movedData, corrupt, "the unopenable file is kept, byte for byte, not deleted")

    let context = ModelContext(result.container)
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 0,
      "the replacement store opens empty")
    context.insert(Rule(pattern: "AFTER*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Rule>()), 1, "and it accepts writes")
    withExtendedLifetime(result.container) {}

    XCTAssertEqual(
      StoreRecoveryRecord.load(from: defaults),
      StoreRecoveryNotice(movedAt: fixedNow, fileName: "default-\(fixedStamp).store"))
  }

  /// A CloudKit failure alone is answered by the local store, and that store is
  /// valid, so nothing moves and nothing is recorded.
  func testACloudKitOnlyFailureMovesNothing() throws {
    try writeValidStore()
    let url = storeURL

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { try NomiModelContainer.makeLocal(at: url) },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    guard case .localOnly = result.mode else {
      return XCTFail("expected the local fallback, got \(result.mode)")
    }
    XCTAssertTrue(result.persistent, "the local store is on disk, so it persists")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: recoveredDirectory.path),
      "no Recovered directory when nothing was moved")
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults))

    let context = ModelContext(result.container)
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 1,
      "the existing rows are still there")
    withExtendedLifetime(result.container) {}
  }

  /// No file exists, so the verdict is `.noStoreFile`. That is a retry, not a
  /// move: there is nothing to record, and the app runs in memory for this
  /// launch only.
  func testWhenNothingOpensTheAppGetsAnInMemoryStore() throws {
    let url = storeURL

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { throw LocalDown() },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    XCTAssertEqual(result.mode, .localOnly(reason: NomiModelContainer.retryLaterReason))
    XCTAssertFalse(result.persistent, "an in-memory launch is not persistent")
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults), "no file was moved, so there is no notice")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: recoveredDirectory.path),
      "no Recovered directory when nothing was moved")

    let context = ModelContext(result.container)
    context.insert(Rule(pattern: "MEMORY*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 1,
      "the in-memory store takes writes, so the app can run")
    withExtendedLifetime(result.container) {}
  }

  /// A corrupt store is moved, a fresh one is tried, and the fresh one also
  /// fails. The app runs in memory with the step 3c reason, and the notice is
  /// kept because the move did happen.
  func testWhenACorruptStoreMovesButTheFreshOneFailsTheAppGetsAnInMemoryStore() throws {
    let url = storeURL
    try Data(repeating: 0, count: 4096).write(to: url)

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { throw LocalDown() },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    XCTAssertEqual(result.mode, .localOnly(reason: noRowsKeptReason))
    XCTAssertFalse(result.persistent)
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: recoveredDirectory.appendingPathComponent("default-\(fixedStamp).store").path),
      "the corrupt file was moved")
    XCTAssertEqual(
      StoreRecoveryRecord.load(from: defaults),
      StoreRecoveryNotice(movedAt: fixedNow, fileName: "default-\(fixedStamp).store"))

    let context = ModelContext(result.container)
    context.insert(Rule(pattern: "MEMORY*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Rule>()), 1)
    withExtendedLifetime(result.container) {}
  }

  /// **The data-protection stand-in (c1, c2).** A valid store made unreadable,
  /// the way a locked device denies `open(2)` before first unlock, must never
  /// be moved. The file is left in place and the app runs in memory this launch.
  /// Skipped under root, which ignores mode bits. The simulator does not enforce
  /// data protection, so there is no on-device proof here.
  func testAProtectedStoreIsNeverMoved() throws {
    try XCTSkipIf(getuid() == 0, "root ignores mode bits, so the denial cannot be simulated")
    try writeValidStore()
    let url = storeURL
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { try NomiModelContainer.makeLocal(at: url) },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    XCTAssertEqual(result.mode, .localOnly(reason: NomiModelContainer.retryLaterReason))
    XCTAssertFalse(result.persistent)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredDirectory.path), "no Recovered directory")
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the store is still at its path")
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults), "no notice is saved")

    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    let reopened = try NomiModelContainer.makeLocal(at: url)
    let context = ModelContext(reopened)
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 1,
      "once readable again, the real store opens with its row")
    withExtendedLifetime(reopened) {}
  }

  /// A valid store whose open fails for a reason other than corruption (a
  /// migration or a lock, here both throwers) must never be moved. The probe
  /// finds the copy intact, so the verdict is a retry.
  func testAValidStoreWhoseOpenFailsIsNeverMoved() throws {
    try writeValidStore()
    let url = storeURL

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { throw LocalDown() },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    XCTAssertEqual(result.mode, .localOnly(reason: NomiModelContainer.retryLaterReason))
    XCTAssertFalse(result.persistent)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredDirectory.path), "no Recovered directory")
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the store is still at its path")
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults), "no notice is saved")

    let reopened = try NomiModelContainer.makeLocal(at: url)
    let context = ModelContext(reopened)
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 1,
      "the store is intact and still has its row")
    withExtendedLifetime(reopened) {}
  }

  /// **Andrews's ruling (c5).** A corrupt file whose move fails stays where it
  /// is, byte for byte. The app falls back to memory with the step 3c reason,
  /// with no retry and no delete. A regular file named `Recovered` beside the
  /// store makes `createDirectory` throw.
  func testAFailedMoveKeepsTheOriginalAndFallsBackToMemory() throws {
    let url = storeURL
    let corrupt = Data(repeating: 0, count: 4096)
    try corrupt.write(to: url)
    try Data("in the way".utf8).write(to: recoveredDirectory)

    let result = NomiModelContainer.makeWithLocalFallback(
      cloudKit: { throw CloudKitDown() },
      isSimulatorDebugBuild: false,
      forceCloudKit: false,
      local: { throw LocalDown() },
      storeURL: url,
      recoveryDefaults: defaults,
      now: { self.fixedNow })

    XCTAssertEqual(try Data(contentsOf: url), corrupt, "the original is byte-identical, not deleted")
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults), "no notice, because nothing moved")
    XCTAssertEqual(result.mode, .localOnly(reason: noRowsKeptReason))
    XCTAssertFalse(result.persistent)

    let context = ModelContext(result.container)
    context.insert(Rule(pattern: "MEMORY*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<Rule>()), 1)
    withExtendedLifetime(result.container) {}
  }

  /// The move takes the `-wal` and `-shm` sidecars with the main file, under the
  /// same stamp. A sidecar left behind would be replayed into the next store.
  func testMoveStoreAsideTakesTheSidecarsAndStampsThemAlike() throws {
    try Data("main".utf8).write(to: storeURL)
    try Data("wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))
    try Data("shm".utf8).write(to: directory.appendingPathComponent("default.store-shm"))

    let moved = try NomiModelContainer.moveStoreAside(
      at: storeURL, stamp: fixedNow, fileManager: .default)

    XCTAssertEqual(moved, "default-\(fixedStamp).store")
    for name in [
      "default-\(fixedStamp).store", "default-\(fixedStamp).store-wal", "default-\(fixedStamp).store-shm",
    ] {
      XCTAssertTrue(
        FileManager.default.fileExists(atPath: recoveredDirectory.appendingPathComponent(name).path),
        "\(name) is in Recovered/")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "the original is gone from the store path")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("default.store-wal").path),
      "no sidecar is left beside the store path")

    let nothing = try NomiModelContainer.moveStoreAside(
      at: storeURL, stamp: fixedNow, fileManager: .default)
    XCTAssertNil(nothing, "with no store files there is nothing to record")
  }

  /// An orphan `-wal` with no main file is still moved out of the store path, so
  /// it cannot be replayed into the next store. It is not a recovery, so the
  /// function returns nil and no notice would be saved.
  func testAnOrphanSidecarIsMovedButIsNotReportedAsARecovery() throws {
    try Data("wal".utf8).write(to: directory.appendingPathComponent("default.store-wal"))

    let moved = try NomiModelContainer.moveStoreAside(
      at: storeURL, stamp: fixedNow, fileManager: .default)

    XCTAssertNil(moved, "no main file existed, so there is no recovery to record")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: recoveredDirectory.appendingPathComponent("default-\(fixedStamp).store-wal").path),
      "the orphan is moved into Recovered/")
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: directory.appendingPathComponent("default.store-wal").path),
      "the orphan is gone from the store path")
  }
}
