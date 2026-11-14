import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// One test per rule of `classifyUnopenableStore` (I-6 Amendment 1, step A1).
/// Each asserts the exact verdict, because the verdict decides whether a user's
/// file is moved. A test that passed on a different verdict would hide that.
///
/// XCTest, with every container held to the end of its test. Each test gets a
/// fresh directory, and the probe's scratch directory is a subdirectory of it.
final class StoreFailureClassifierTests: XCTestCase {
  private var directory: URL!
  private var scratch: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    scratch = directory.appendingPathComponent("scratch", isDirectory: true)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
  }

  private var storeURL: URL {
    directory.appendingPathComponent("default.store")
  }

  private func classify(_ url: URL? = nil, scratchDirectory: URL? = nil) -> NomiModelContainer.StoreFailureVerdict {
    NomiModelContainer.classifyUnopenableStore(
      at: url ?? storeURL,
      fileManager: .default,
      scratchDirectory: scratchDirectory ?? scratch)
  }

  /// A valid V1 store with two rows, written through `makeLocal(at:)`. The
  /// container is returned so the caller decides when it is released.
  private func writeValidStore() throws -> ModelContainer {
    let container = try NomiModelContainer.makeLocal(at: storeURL)
    let context = ModelContext(container)
    context.insert(Rule(pattern: "SWIGGY*", categoryID: UUID()))
    context.insert(Rule(pattern: "ZOMATO*", categoryID: UUID()))
    try context.save()
    return container
  }

  /// Rule 1: no file at the store's path.
  func testAMissingFileIsRetry() {
    XCTAssertEqual(classify(), .retryLater(.noStoreFile))
  }

  /// Rule 2: the file exists but cannot be opened. A mode of 0o000 denies
  /// `open(2)` the way a locked device does before first unlock. Root ignores
  /// mode bits, so the test is skipped there.
  func testAnUnreadableFileIsRetry() throws {
    try XCTSkipIf(getuid() == 0, "root ignores mode bits, so the denial cannot be simulated")
    let container = try writeValidStore()
    withExtendedLifetime(container) {}
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path) }

    XCTAssertEqual(classify(), .retryLater(.unreadable))
  }

  /// Rule 3: a zero-byte file is not a database, but there is nothing to
  /// recover, so it is retried, not moved.
  func testAnEmptyFileIsRetry() throws {
    try Data().write(to: storeURL)
    XCTAssertEqual(classify(), .retryLater(.emptyFile))
  }

  /// Rule 4: 4 KB of zeros has no SQLite header. That is corruption, from the
  /// bytes alone.
  func testFourKBOfZerosIsCorrupt() throws {
    try Data(repeating: 0, count: 4096).write(to: storeURL)
    XCTAssertEqual(classify(), .corrupt(.notSQLiteHeader))
  }

  /// Rule 4, short files: 1 to 15 bytes never equal the 16-byte header.
  func testAShortNonSQLiteFileIsCorrupt() throws {
    try Data("hello".utf8).write(to: storeURL)
    XCTAssertEqual(classify(), .corrupt(.notSQLiteHeader))
  }

  /// Rule 7: the header is right, but the pages are garbage. SQLite reports
  /// corruption on open or on the integrity check, and either is corrupt.
  func testAValidHeaderOverGarbageIsCorrupt() throws {
    var bytes = Array("SQLite format 3\u{0}".utf8)
    bytes += [UInt8](repeating: 0xFF, count: 4080)
    try Data(bytes).write(to: storeURL)
    XCTAssertEqual(classify(), .corrupt(.integrityCheckFailed))
  }

  /// Rule 7, the healthy case: a real store passes `quick_check`, so it is not
  /// moved. A failed open with a healthy file is a retry, every launch.
  func testAValidV1StoreIsIntact() throws {
    let container = try writeValidStore()
    XCTAssertEqual(classify(), .retryLater(.storeIntact))
    withExtendedLifetime(container) {}
  }

  /// Rule 5: the probe cannot copy the file, because the scratch directory is
  /// not writable. Disk full lands here too. The answer is a retry, never a move.
  func testAnUnwritableScratchDirectoryIsRetry() throws {
    try XCTSkipIf(getuid() == 0, "root ignores mode bits, so the denial cannot be simulated")
    let container = try writeValidStore()
    withExtendedLifetime(container) {}
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: scratch.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scratch.path) }

    XCTAssertEqual(classify(scratchDirectory: scratch), .retryLater(.probeCopyFailed))
  }

  /// The probe removes its copy on every path, so the scratch directory is
  /// left as it was found.
  func testTheProbeLeavesNoScratchBehind() throws {
    let container = try writeValidStore()
    XCTAssertEqual(classify(), .retryLater(.storeIntact))

    let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.path)
      .filter { $0.hasPrefix("nomi-store-probe-") }
    XCTAssertEqual(leftovers, [], "no probe directory survives the classification")
    withExtendedLifetime(container) {}
  }

  /// The probe works on a copy. With a `-wal` present, the store and the WAL
  /// keep their size and modification date through the classification.
  func testTheProbeNeverModifiesTheStore() throws {
    let container = try writeValidStore()
    let walURL = directory.appendingPathComponent("default.store-wal")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: walURL.path),
      "the store must still have its WAL for this test to mean anything")

    let before = try snapshot(of: [storeURL, walURL])
    XCTAssertEqual(classify(), .retryLater(.storeIntact))
    let after = try snapshot(of: [storeURL, walURL])

    XCTAssertEqual(before, after, "neither the store nor its WAL is written by the probe")
    withExtendedLifetime(container) {}
  }

  /// Size and modification date for each file, in a comparable form.
  private func snapshot(of urls: [URL]) throws -> [String] {
    try urls.map { url in
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let size = attributes[.size] as? NSNumber
      let modified = attributes[.modificationDate] as? Date
      return "\(url.lastPathComponent) size=\(size?.stringValue ?? "?") mtime=\(modified?.timeIntervalSince1970 ?? 0)"
    }
  }
}
