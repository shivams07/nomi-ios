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

  /// The two keys this test is about, decoded rather than fished out of an
  /// `Any`.
  ///
  /// The first version used `PropertyListSerialization` and
  /// `as? [String: Any]`, and both keys came back `nil` on CI while the file
  /// read fine — an untyped cast that fails silently and reports only the
  /// symptom. A `Decodable` either produces these fields or throws saying
  /// which one it could not read.
  private struct Entitlements: Decodable {
    let containerIdentifiers: [String]?
    let services: [String]?

    enum CodingKeys: String, CodingKey {
      case containerIdentifiers = "com.apple.developer.icloud-container-identifiers"
      case services = "com.apple.developer.icloud-services"
    }
  }

  private struct EntitlementsUnreadable: Error, CustomStringConvertible {
    let path: String
    var description: String {
      """
      Could not read the entitlements at \(path). If this file moved, fix the       path — do not delete this test. It is the only check that the app's       CloudKit container identifier matches the one the code asks for, and a       mismatch is an uncatchable crash rather than an error.
      """
    }
  }

  private func entitlements() throws -> Entitlements {
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
      // Throws rather than returning an empty value. Returning one would let
      // the assertions below fail with "nil is not equal to …", which says
      // nothing about the file being missing — the failure has to name the
      // path or it sends the reader looking in the wrong place.
      throw EntitlementsUnreadable(path: url.path)
    }
    decodedFromDisk = String(data: data, encoding: .utf8) ?? "<not UTF-8, \(data.count) bytes>"
    return try PropertyListDecoder().decode(Entitlements.self, from: data)
  }

  /// What was actually on disk, carried into the failure messages.
  ///
  /// Both assertions failed twice with "nil is not equal to …", which says the
  /// key was absent but not *why* — and the file is correct in git, so the
  /// interesting question is what the file looked like by the time the test
  /// ran. A parity test whose failure does not show both sides of the
  /// comparison sends the reader to the wrong file.
  private var decodedFromDisk = "<not read>"


  /// The parity that matters: a mismatch here means the app asks CloudKit for
  /// a container it is not entitled to use, and crashes on first sync.
  func testTheEntitlementsNameTheContainerTheCodeAsksFor() throws {
    let identifiers = try entitlements().containerIdentifiers

    XCTAssertEqual(
      identifiers, [NomiModelContainer.cloudKitContainerIdentifier],
      """
      App/Nomi.entitlements and NomiModelContainer.cloudKitContainerIdentifier       disagree. Whichever one is wrong, the build crashes on first CloudKit       access - there is no runtime check that can catch this.

      On disk at test time:
      \(decodedFromDisk)
      """)
  }

  /// The identifier being right is not enough on its own: without the CloudKit
  /// service the entitlement grants nothing, and the failure looks identical.
  func testTheEntitlementsEnableCloudKitItself() throws {
    let services = try entitlements().services

    XCTAssertEqual(
      services, ["CloudKit"],
      """
      App/Nomi.entitlements does not enable the CloudKit service.

      On disk at test time:
      \(decodedFromDisk)
      """)
  }
}
