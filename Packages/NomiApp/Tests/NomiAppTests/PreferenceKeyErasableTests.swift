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

  /// MKIND (Lim's gap). Each entry's kind must match how its real writer stores
  /// the value: a `.bool` key through the Bool overload, a `.data` key through the
  /// Data overload. Each writer is driven against a recording store, and every key
  /// must have been written, so a key no writer reached fails rather than passing.
  @MainActor
  func testEachErasableKindMatchesHowItsWriterStoresIt() async throws {
    let spy = KindRecordingStore()

    FirstRunGate(store: spy).completeFirstRun()  // hasCompletedFirstRun, bool
    NotificationSettingsStore(store: spy, scheduler: NoopNotificationScheduler())
      .update(NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.75))  // notificationSettings, data

    let credentials = MemoryCredentialStore()
    try credentials.save(.test)
    let stack = MailStack(
      fetcher: OrderRecordingMailFetcher(),
      pipeline: SilentPipeline(),
      credentials: credentials,
      preferences: spy)
    try await stack.service.connect(.test)  // mailHasConnected, bool
    try await stack.syncNow()  // mailSyncCursor and mailLastSyncAt, data
    _ = try await stack.service.startBackfill(months: 1)  // mailBackfillUnfinished, bool

    let boolWrites = spy.boolWrites()
    let dataWrites = spy.dataWrites()
    for entry in PreferenceKey.erasable {
      XCTAssertTrue(
        boolWrites.contains(entry.key) || dataWrites.contains(entry.key),
        "no writer reached \(entry.key), so its kind is unchecked")
      switch entry.kind {
      case .bool:
        XCTAssertTrue(boolWrites.contains(entry.key), "\(entry.key) is listed as bool, but its writer does not store a Bool")
        XCTAssertFalse(dataWrites.contains(entry.key), "\(entry.key) is listed as bool, but its writer stores data")
      case .data:
        XCTAssertTrue(dataWrites.contains(entry.key), "\(entry.key) is listed as data, but its writer does not store Data")
        XCTAssertFalse(boolWrites.contains(entry.key), "\(entry.key) is listed as data, but its writer stores a Bool")
      }
    }
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

/// Keeps the values so reads behave, and records which overload each key was
/// written through. The overload is what the kind check is about.
private final class KindRecordingStore: KeyValueStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Any] = [:]
  private var boolKeys: Set<String> = []
  private var dataKeys: Set<String> = []

  func bool(forKey key: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return values[key] as? Bool ?? false
  }

  func set(_ value: Bool, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    values[key] = value
    boolKeys.insert(key)
  }

  func data(forKey key: String) -> Data? {
    lock.lock()
    defer { lock.unlock() }
    return values[key] as? Data
  }

  func set(_ value: Data?, forKey key: String) {
    lock.lock()
    defer { lock.unlock() }
    if let value {
      values[key] = value
    } else {
      values.removeValue(forKey: key)
    }
    dataKeys.insert(key)
  }

  func boolWrites() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return boolKeys
  }

  func dataWrites() -> Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return dataKeys
  }
}
