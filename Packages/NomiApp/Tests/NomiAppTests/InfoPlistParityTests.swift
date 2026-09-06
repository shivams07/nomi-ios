import Foundation
import XCTest

@testable import NomiApp

/// `App/Info.plist` is hand-maintained and load-bearing, and nothing else in
/// the test suite reads it.
///
/// Two of its keys are the kind that fail late and badly. Registering a
/// background task whose identifier is absent from
/// `BGTaskSchedulerPermittedIdentifiers` is a crash at registration, not a
/// warning — `AppSyncCoordinator.TaskIdentifier`'s own doc comment says so.
/// And `UIBackgroundModes` missing `fetch`/`processing` does not fail at all:
/// the app launches, registers, and is simply never woken, which looks
/// identical to "no mail arrived".
///
/// Reads the plist from `#filePath` rather than a bundle resource: the file
/// belongs to the Xcode app target, not to this SwiftPM test target, so there
/// is no bundle to find it in. That makes this test sensitive to being moved —
/// hence the explicit throw below rather than a silent skip, which would leave
/// the guard looking green while checking nothing.
///
/// Note the asymmetry this test is built to catch: it reads what is *on disk
/// at test time*, not what is committed. Those differ on CI, where
/// `xcodegen generate` runs before the test steps.
final class InfoPlistParityTests: XCTestCase {

  /// The two keys this test is about, decoded rather than fished out of an
  /// `Any`. An untyped `as? [String: Any]` reports a missing key and a
  /// wrong-typed key identically, and both come back `nil`.
  private struct InfoPlist: Decodable {
    let permittedIdentifiers: [String]?
    let backgroundModes: [String]?

    enum CodingKeys: String, CodingKey {
      case permittedIdentifiers = "BGTaskSchedulerPermittedIdentifiers"
      case backgroundModes = "UIBackgroundModes"
    }
  }

  private struct InfoPlistUnreadable: Error, CustomStringConvertible {
    let path: String
    var description: String {
      """
      Could not read the Info.plist at \(path). If this file moved, fix the \
      path — do not delete this test. It is the only check that the app is \
      permitted to run the background tasks it registers, and an identifier \
      the plist does not list is a crash at registration.
      """
    }
  }

  /// What was actually on disk, carried into the failure messages.
  ///
  /// A parity test whose failure does not show both sides of the comparison
  /// sends the reader to the committed file, which may well be correct — that
  /// is precisely the case this test exists to distinguish.
  private var readFromDisk = "<not read>"

  private func infoPlist() throws -> InfoPlist {
    // …/Packages/NomiApp/Tests/NomiAppTests/InfoPlistParityTests.swift
    //  → repo root is five levels up.
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
      .deletingLastPathComponent()  // Packages
      .deletingLastPathComponent()  // repo root
    let url = repoRoot.appending(path: "App/Info.plist")

    guard let data = try? Data(contentsOf: url) else {
      // Throws rather than returning an empty value: an empty one would fail
      // the assertions below with "nil is not equal to …", which says nothing
      // about the file being missing and sends the reader to the wrong file.
      throw InfoPlistUnreadable(path: url.path)
    }
    readFromDisk = String(data: data, encoding: .utf8) ?? "<not UTF-8, \(data.count) bytes>"
    return try PropertyListDecoder().decode(InfoPlist.self, from: data)
  }

  /// The parity that crashes: an identifier the app registers but the plist
  /// does not permit terminates the app at registration.
  ///
  /// Compared as a `Set`. "Exactly these two identifiers, no more and no
  /// fewer" is the actual requirement; the order they appear in the array
  /// carries no meaning, and asserting on it would fail a harmless reorder.
  func testTheBackgroundTaskIdentifiersMatchTheOnesTheCoordinatorRegisters() throws {
    let permitted = try infoPlist().permittedIdentifiers

    let declared: Set<String> = [
      AppSyncCoordinator.TaskIdentifier.refresh,
      AppSyncCoordinator.TaskIdentifier.backfill,
    ]

    XCTAssertEqual(
      permitted.map { Set($0) }, declared,
      """
      App/Info.plist's BGTaskSchedulerPermittedIdentifiers and \
      AppSyncCoordinator.TaskIdentifier disagree. Registering an identifier \
      the plist does not permit is a crash at registration, not an error \
      anything can catch.

      On disk at test time:
      \(readFromDisk)
      """)
  }

  /// The parity that fails silently: without these modes the app is never
  /// woken, and the background tasks it registered simply never run.
  ///
  /// `contains` rather than equality — a mode added later for an unrelated
  /// reason is not this test's business.
  func testTheBackgroundModesAllowFetchAndProcessing() throws {
    let modes = try infoPlist().backgroundModes ?? []

    XCTAssertTrue(
      modes.contains("fetch") && modes.contains("processing"),
      """
      App/Info.plist's UIBackgroundModes must contain both "fetch" and \
      "processing"; it has \(modes). Missing these does not throw or crash — \
      the app registers its tasks and is never woken to run them, which is \
      indistinguishable from no mail having arrived.

      On disk at test time:
      \(readFromDisk)
      """)
  }
}
