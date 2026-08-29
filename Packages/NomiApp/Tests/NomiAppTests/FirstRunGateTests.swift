import XCTest

@testable import NomiApp

/// The acceptance criterion in one file: "a first run lands on onboarding and a
/// subsequent run does not".
@MainActor
final class FirstRunGateTests: XCTestCase {

  func testAFirstRunLandsOnOnboarding() {
    XCTAssertEqual(FirstRunGate.initialRoute(hasCompletedFirstRun: false), .onboarding(.connectMail))
  }

  func testASubsequentRunDoesNot() {
    XCTAssertEqual(FirstRunGate.initialRoute(hasCompletedFirstRun: true), .main)
  }

  func testAFreshStoreOpensOnOnboarding() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    XCTAssertEqual(gate.route, .onboarding(.connectMail))
  }

  /// The flag survives a relaunch — the same key-value store, a new gate, which
  /// is what a second launch is.
  func testCompletingFirstRunPersistsAcrossRelaunch() {
    let store = InMemoryKeyValueStore()

    let first = FirstRunGate(store: store)
    first.completeFirstRun()
    XCTAssertEqual(first.route, .main)

    let second = FirstRunGate(store: store)
    XCTAssertEqual(second.route, .main)
  }

  func testConnectingMailDuringOnboardingAdvancesToBackfill() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.mailConnected()
    XCTAssertEqual(gate.route, .onboarding(.backfill))
  }

  /// The trap this guard exists for. `ConnectMailScreen` fires
  /// `onBackfillStart` every time it observes `.connected`, and Settings pushes
  /// that same screen for an established user. Without the guard, re-entering an
  /// app password months later throws the user back into onboarding and starts a
  /// six-month backfill.
  func testConnectingMailAfterFirstRunDoesNotReopenOnboarding() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.completeFirstRun()

    gate.mailConnected()

    XCTAssertEqual(gate.route, .main)
  }

  /// Skipping is a complete first run. A user who declines to hand over a
  /// mailbox password — or who cannot connect, because this build has no IMAP
  /// transport — must not be asked again on every launch.
  func testSkippingWithoutConnectingStillCompletesFirstRun() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)

    gate.completeFirstRun()

    XCTAssertTrue(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
    XCTAssertEqual(FirstRunGate(store: store).route, .main)
  }

  func testResetReturnsToOnboardingAndClearsTheFlag() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.completeFirstRun()

    gate.resetForTesting()

    XCTAssertEqual(gate.route, .onboarding(.connectMail))
    XCTAssertFalse(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }
}

final class KeyValueStoreTests: XCTestCase {
  func testBoolDefaultsToFalseForAnUnsetKey() {
    XCTAssertFalse(InMemoryKeyValueStore().bool(forKey: "absent"))
  }

  func testDataRoundTrips() {
    let store = InMemoryKeyValueStore()
    store.set(Data([1, 2, 3]), forKey: "k")
    XCTAssertEqual(store.data(forKey: "k"), Data([1, 2, 3]))
  }

  func testSettingNilClearsTheValue() {
    let store = InMemoryKeyValueStore()
    store.set(Data([1]), forKey: "k")
    store.set(nil, forKey: "k")
    XCTAssertNil(store.data(forKey: "k"))
  }

  /// Every key the app writes lives on one type, so a collision is visible.
  /// Asserting they are distinct is cheap and catches a copy-paste.
  func testPreferenceKeysAreDistinct() {
    let keys = [
      PreferenceKey.hasCompletedFirstRun,
      PreferenceKey.notificationSettings,
      PreferenceKey.mailSyncCursor,
    ]
    XCTAssertEqual(Set(keys).count, keys.count)
  }
}
