import Foundation
import NomiCore
import XCTest

@testable import NomiApp

/// I-13 Amendment 1, B5a step 4 (G6). Erase clears exactly the preferences the
/// app writes. The list is fixed by hand, so a key added later must be made
/// erasable by hand as well: the source scan below fails when it is not.
final class PreferenceKeyErasableTests: XCTestCase {

  /// The source of `Packages/NomiApp`, found from this file's own path, so the
  /// scan reads the code that is actually built and not a copy.
  private func packageSource(_ relativePath: String, file: StaticString = #filePath) throws -> String {
    let root = URL(fileURLWithPath: "\(file)")
      .deletingLastPathComponent()  // NomiAppTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // Packages/NomiApp
    return try String(
      contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
  }

  /// Every `static let <name> = "nomi.…"` inside `PreferenceKey`, by value.
  private func preferenceKeyValues(in source: String) throws -> Set<String> {
    let start = try XCTUnwrap(source.range(of: "public enum PreferenceKey"))
    let body = String(source[start.lowerBound...])
    let regex = try NSRegularExpression(pattern: #"static let \w+ = "(nomi\.[^"]+)""#)
    let matches = regex.matches(in: body, range: NSRange(body.startIndex..., in: body))
    return Set(matches.compactMap { match in
      Range(match.range(at: 1), in: body).map { String(body[$0]) }
    })
  }

  /// Every key in `PreferenceKey` is either erasable or one of the standard
  /// defaults erased by name. The one standard-defaults key that lives in
  /// `PreferenceKey` is `dismissedRecurringSeries`, so it is expected here too.
  func testEveryPreferenceKeyIsErasableOrDeclaredAsAStandardDefault() throws {
    let source = try packageSource("Sources/NomiApp/Support/KeyValueStore.swift")
    let scanned = try preferenceKeyValues(in: source)
    XCTAssertFalse(scanned.isEmpty, "the scan found no keys, so the regex is wrong")

    let erasable = Set(PreferenceKey.erasable.map(\.key))
    let expected = erasable.union([PreferenceKey.dismissedRecurringSeries])

    XCTAssertEqual(
      scanned, expected,
      "a key added to PreferenceKey must be listed in PreferenceKey.erasable (or standardDefaultsErasable)")
  }

  func testTheErasableListHasNoDuplicateKeys() {
    let keys = PreferenceKey.erasable.map(\.key)
    XCTAssertEqual(Set(keys).count, keys.count)
  }

  func testTheStandardDefaultsListNamesTheRecoveryRecordAndTheDismissal() {
    XCTAssertTrue(PreferenceKey.standardDefaultsErasable.contains(StoreRecoveryRecord.defaultsKey))
    XCTAssertTrue(PreferenceKey.standardDefaultsErasable.contains(PreferenceKey.dismissedRecurringSeries))
  }

  /// B6's dismissal store keeps its own literal. This pins the two strings
  /// together, read from that file's source.
  func testDismissedRecurringSeriesKeyEqualsTheLiteralItsStoreWrites() throws {
    let source = try packageSource("Sources/NomiApp/Insights/SwiftDataRecurringStore.swift")
    let regex = try NSRegularExpression(pattern: #"static let dismissedKey = "([^"]+)""#)
    let match = try XCTUnwrap(regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)))
    let literal = try XCTUnwrap(Range(match.range(at: 1), in: source).map { String(source[$0]) })

    XCTAssertEqual(PreferenceKey.dismissedRecurringSeries, literal)
  }
}
