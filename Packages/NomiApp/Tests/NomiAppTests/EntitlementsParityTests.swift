import Foundation
import XCTest

@testable import NomiApp

/// The guard for the condition U9b **cannot** check at runtime.
///
/// A build whose entitlements do not name the container the code asks for does
/// not report an error, throw, or return a status — `CKContainer` raises an
/// uncatchable ObjC exception, which is a crash. There is no public API to ask
/// "am I entitled?" before that happens, so the only honest place to catch it
/// is here, at build time, by comparing the two files that have to agree.
///
/// This is not a hypothetical failure. It is exactly what killed CI run
/// 33994342474 — an unentitled `swift test` process reaching CloudKit and
/// dying with signal 5.
///
/// Reads the entitlements from `#filePath` rather than a bundle resource: the
/// file belongs to the Xcode app target, not to this SwiftPM test target, so
/// there is no bundle to find it in. That makes this test sensitive to being
/// moved — hence the explicit failure message below rather than a silent skip,
/// which would leave the guard looking green while checking nothing.
final class EntitlementsParityTests: XCTestCase {

  private func entitlements() throws -> [String: Any] {
    // …/Packages/NomiApp/Tests/NomiAppTests/EntitlementsParityTests.swift
    //  → repo root is five levels up.
    let repoRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // NomiApp
      .deletingLastPathComponent()  // Packages
      .deletingLastPathComponent()  // repo root
    let url = repoRoot.appending(path: "App/Nomi.entitlements")

    guard let data = try? Data(contentsOf: url) else {
      XCTFail(
        """
        Could not read App/Nomi.entitlements at \(url.path). If this file moved, \
        fix the path — do not delete this test. It is the only check that the \
        app's CloudKit container identifier matches the one the code asks for, \
        and a mismatch is an uncatchable crash rather than an error.
        """)
      return [:]
    }
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    return plist as? [String: Any] ?? [:]
  }

  /// The parity that matters: a mismatch here means the app asks CloudKit for
  /// a container it is not entitled to use, and crashes on first sync.
  func testTheEntitlementsNameTheContainerTheCodeAsksFor() throws {
    let identifiers =
      try entitlements()["com.apple.developer.icloud-container-identifiers"] as? [String]

    XCTAssertEqual(
      identifiers, [NomiModelContainer.cloudKitContainerIdentifier],
      """
      App/Nomi.entitlements and NomiModelContainer.cloudKitContainerIdentifier \
      disagree. Whichever one is wrong, the build crashes on first CloudKit \
      access - there is no runtime check that can catch this.
      """)
  }

  /// The identifier being right is not enough on its own: without the CloudKit
  /// service the entitlement grants nothing, and the failure looks identical.
  func testTheEntitlementsEnableCloudKitItself() throws {
    let services = try entitlements()["com.apple.developer.icloud-services"] as? [String]

    XCTAssertEqual(services, ["CloudKit"])
  }
}
