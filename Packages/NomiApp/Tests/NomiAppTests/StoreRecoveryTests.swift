import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// The recovery path of `makeWithLocalFallback` (R7, I-6): a store that will not
/// open is moved aside, recorded, and replaced; the app launches either way.
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

  /// **The recovery proof.** A 4 KB file of zeros at the store's path is not a
  /// database. The app must move it aside rather than delete it, record the
  /// move, open a fresh empty store, and launch.
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

  /// When nothing opens, not even a fresh store, the app runs on an in-memory
  /// store and says so. Nothing exists on disk here, so nothing moves.
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

    XCTAssertEqual(result.mode, .localOnly(reason: noRowsKeptReason))
    XCTAssertNil(StoreRecoveryRecord.load(from: defaults), "no file was moved, so there is no notice")

    let context = ModelContext(result.container)
    context.insert(Rule(pattern: "MEMORY*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(
      try context.fetchCount(FetchDescriptor<Rule>()), 1,
      "the in-memory store takes writes, so the app can run")
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
