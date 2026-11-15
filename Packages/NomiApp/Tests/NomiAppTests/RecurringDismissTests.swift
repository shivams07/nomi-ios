import Foundation
import NomiCore
import NomiPreview
import SwiftData
import XCTest

@testable import NomiApp

/// B6 (I-14), recurring-series dismissal. A dismissed series is hidden from
/// `recurringSeries()` on this device, immediately and after a new store
/// instance. The dismissed ids live in the launch's preference store (the same
/// seam as the first-run flag), not in the SwiftData store, so there is no
/// schema change.
///
/// Most tests use `InMemoryKeyValueStore`, so nothing reaches `UserDefaults`.
/// The one test that does reach a `UserDefaults` suite removes it in
/// `tearDownWithError`. XCTest, not swift-testing, for the container-lifetime
/// reason in `RecurringStoreTests`.
@MainActor
final class RecurringDismissTests: XCTestCase {

  /// Owns each test's container for the life of the test. See `InMemoryStack`.
  private var stacks: [InMemoryStack] = []
  private var suiteNames: [String] = []

  override func tearDownWithError() throws {
    for name in suiteNames {
      UserDefaults.standard.removePersistentDomain(forName: name)
    }
    suiteNames = []
    stacks = []
  }

  func testDismissedSeriesIsHidden() throws {
    let fixture = try makeFixture()
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)
    XCTAssertEqual(
      try fixture.store.recurringSeries().map(\.id), ["NETFLIX"], "visible before dismissal")
    let missesBefore = fixture.cache.missCount

    try fixture.store.dismiss(seriesID: "NETFLIX")

    XCTAssertTrue(try fixture.store.recurringSeries().isEmpty, "hidden on the very next read")
    XCTAssertEqual(fixture.store.dismissedSeriesIDs(), ["NETFLIX"])
    XCTAssertEqual(
      fixture.cache.missCount, missesBefore,
      "the read after the dismissal is a cache hit: the cache keeps the unfiltered answer")
  }

  func testDismissalSurvivesANewStore() throws {
    let fixture = try makeFixture()
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)
    try fixture.store.dismiss(seriesID: "NETFLIX")

    // A new store with a new cache, on the same context and the same preference
    // store: what a relaunch looks like, as far as this feature is concerned.
    let reopened = makeStore(
      context: fixture.context, cache: InsightsCache(), preferences: fixture.preferences)

    XCTAssertTrue(try reopened.recurringSeries().isEmpty)
    XCTAssertEqual(reopened.dismissedSeriesIDs(), ["NETFLIX"])
  }

  /// I-6 Amendment 2: nothing a non-persistent launch writes outlives it. The
  /// launch's preference store is a read-through overlay over what the user last
  /// saved, so a dismissal here stays out of `UserDefaults` and the next launch
  /// does not see it. The production `UserDefaults.standard` default was the
  /// leak this guards against (PR #195 review).
  func testADismissalInAMemoryLaunchDoesNotOutliveIt() throws {
    let key = SwiftDataRecurringStore.dismissedKey
    let suiteName = "RecurringDismissTests.\(UUID().uuidString)"
    suiteNames.append(suiteName)
    let saved = UserDefaultsKeyValueStore(defaults: UserDefaults(suiteName: suiteName)!)
    let standardBefore = UserDefaults.standard.data(forKey: key)

    let fixture = try makeFixture(preferences: ReadThroughKeyValueStore(reading: saved))
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)
    try fixture.store.dismiss(seriesID: "NETFLIX")

    XCTAssertTrue(try fixture.store.recurringSeries().isEmpty, "hidden in this launch")
    XCTAssertEqual(
      UserDefaults.standard.data(forKey: key), standardBefore,
      "a dismissal does not reach UserDefaults.standard")
    XCTAssertNil(saved.data(forKey: key), "nor the saved preference the next launch reads")

    let nextLaunch = makeStore(
      context: fixture.context, cache: InsightsCache(),
      preferences: ReadThroughKeyValueStore(reading: saved))
    XCTAssertEqual(nextLaunch.dismissedSeriesIDs(), [], "the next launch sees nothing dismissed")
  }

  /// A value that does not decode reads as nothing dismissed, and a dismissal
  /// written over it works. Nothing is hidden because of garbage in storage.
  func testCorruptValueReadsAsNone() throws {
    let fixture = try makeFixture()
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)

    fixture.preferences.set(Data("not json {".utf8), forKey: SwiftDataRecurringStore.dismissedKey)
    XCTAssertEqual(fixture.store.dismissedSeriesIDs(), [], "garbage is no dismissals")
    XCTAssertEqual(
      try fixture.store.recurringSeries().map(\.id), ["NETFLIX"], "and nothing is hidden")

    fixture.preferences.set(
      Data(#"{"NETFLIX":true}"#.utf8), forKey: SwiftDataRecurringStore.dismissedKey)
    XCTAssertEqual(
      fixture.store.dismissedSeriesIDs(), [], "well-formed JSON of the wrong shape too")

    try fixture.store.dismiss(seriesID: "NETFLIX")
    XCTAssertTrue(
      try fixture.store.recurringSeries().isEmpty, "a new dismissal replaces the corrupt value")
  }

  func testOtherSeriesUnaffected() throws {
    let fixture = try makeFixture()
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)
    insertRun(
      descriptionText: "SPOTIFY INDIA", normalized: "SPOTIFY INDIA", daysAgo: [60, 30, 0],
      into: fixture.context)
    let before = try fixture.store.recurringSeries()
    XCTAssertEqual(
      Set(before.map(\.id)), ["NETFLIX", "SPOTIFY INDIA"], "both visible before dismissal")

    try fixture.store.dismiss(seriesID: "NETFLIX")

    let after = try fixture.store.recurringSeries()
    XCTAssertEqual(after.map(\.id), ["SPOTIFY INDIA"])
    XCTAssertEqual(
      after.first, before.first { $0.id == "SPOTIFY INDIA" }, "unchanged, not just present")
  }

  /// I-14: ids are the normalized descriptions, compared exactly. A dismissal
  /// of a differently-cased id hides nothing.
  func testIdsAreCaseSensitive() throws {
    let fixture = try makeFixture()
    insertRun(
      descriptionText: "NETFLIX SUBSCRIPTION", normalized: "NETFLIX", daysAgo: [60, 30, 0],
      into: fixture.context)

    try fixture.store.dismiss(seriesID: "netflix")

    XCTAssertEqual(try fixture.store.recurringSeries().map(\.id), ["NETFLIX"])
  }

  /// I-14: the stored form is a JSON array, sorted. Dismissing an id that no
  /// series has is stored and harmless, and a repeat is not a second entry.
  func testDismissedIDsReportsWhatWasStored() throws {
    let fixture = try makeFixture()
    XCTAssertEqual(fixture.store.dismissedSeriesIDs(), [])

    try fixture.store.dismiss(seriesID: "SPOTIFY INDIA")
    try fixture.store.dismiss(seriesID: "NETFLIX")
    try fixture.store.dismiss(seriesID: "NETFLIX")
    try fixture.store.dismiss(seriesID: "NOT A SERIES")

    XCTAssertEqual(
      fixture.store.dismissedSeriesIDs(), ["NETFLIX", "NOT A SERIES", "SPOTIFY INDIA"])
    let raw = try XCTUnwrap(fixture.preferences.data(forKey: SwiftDataRecurringStore.dismissedKey))
    XCTAssertEqual(
      try JSONDecoder().decode([String].self, from: raw),
      ["NETFLIX", "NOT A SERIES", "SPOTIFY INDIA"])
  }

  /// The preview store has its own in-memory set. A dismissal hides the series
  /// and is reported back, as the real store does, so a screen built on the
  /// fake behaves the same in previews and tests.
  func testTheFakeStoreHidesADismissedSeries() throws {
    let fake = FakeRecurringStore(series: FakeRecurringStore.sampleSeries)
    XCTAssertEqual(
      try fake.recurringSeries().map(\.id), ["NETFLIX", "SPOTIFY INDIA", "CULT FIT MEMBERSHIP"])

    try fake.dismiss(seriesID: "NETFLIX")

    XCTAssertEqual(try fake.recurringSeries().map(\.id), ["SPOTIFY INDIA", "CULT FIT MEMBERSHIP"])
    XCTAssertEqual(fake.dismissedSeriesIDs(), ["NETFLIX"])
  }

  // MARK: -

  /// The same fixed instant and IST calendar as `RecurringStoreTests`, so the
  /// six-month window does not move with the machine.
  private let reference = Date(timeIntervalSince1970: 1_777_000_000)

  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  private func date(daysAgo days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: reference)!
  }

  private func insertRun(
    descriptionText: String, normalized: String, daysAgo days: [Int], into context: ModelContext
  ) {
    for day in days {
      context.insert(
        Transaction(
          date: date(daysAgo: day),
          descriptionText: descriptionText,
          normalizedDescription: normalized,
          amountMinor: 49900))
    }
    try? context.save()
  }

  private struct Fixture {
    let store: SwiftDataRecurringStore
    let context: ModelContext
    let cache: InsightsCache
    let preferences: any KeyValueStoring
  }

  private func makeFixture(
    preferences: any KeyValueStoring = InMemoryKeyValueStore()
  ) throws -> Fixture {
    let stack = try InMemoryStack()
    stacks.append(stack)
    let cache = InsightsCache()
    let store = makeStore(context: stack.context, cache: cache, preferences: preferences)
    return Fixture(
      store: store, context: stack.context, cache: cache, preferences: preferences)
  }

  private func makeStore(
    context: ModelContext, cache: InsightsCache, preferences: any KeyValueStoring
  ) -> SwiftDataRecurringStore {
    // Copied out rather than captured through `self`, as in `RecurringStoreTests`.
    let moment = reference
    return SwiftDataRecurringStore(
      context: context,
      cache: cache,
      calendar: calendar,
      now: { moment },
      dismissals: preferences)
  }
}
