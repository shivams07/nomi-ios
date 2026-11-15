import XCTest

@testable import NomiApp

/// The acceptance criterion in one file: "a first run lands on onboarding and a
/// subsequent run does not".
@MainActor
final class FirstRunGateTests: XCTestCase {

  func testAFirstRunLandsOnWelcome() {
    XCTAssertEqual(FirstRunGate.initialRoute(hasCompletedFirstRun: false), .onboarding(.welcome))
  }

  func testASubsequentRunDoesNot() {
    XCTAssertEqual(FirstRunGate.initialRoute(hasCompletedFirstRun: true), .main)
  }

  func testAFreshStoreOpensOnWelcome() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    XCTAssertEqual(gate.route, .onboarding(.welcome))
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

  // MARK: - The Welcome and Bring in your data steps

  func testGetStartedOpensBringData() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()
    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  func testChoosingEmailOpensConnectMail() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()
    gate.chooseMail()
    XCTAssertEqual(gate.route, .onboarding(.connectMail))
  }

  func testChoosingAStatementOpensImport() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()
    gate.chooseImport()
    XCTAssertEqual(gate.route, .onboarding(.importStatement))
  }

  /// "Add by hand" is a complete first run, the same as Skip: the flag is set
  /// and the route is `.main`.
  func testChoosingByHandCompletesFirstRunAndSetsTheFlag() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.start()

    gate.chooseManual()

    XCTAssertEqual(gate.route, .main)
    XCTAssertTrue(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// A step can only be reached from the step before it. Each transition is a
  /// no-op from any other route, so a button wired to the wrong step cannot skip
  /// Welcome or jump across Bring in your data.
  func testBringDataChoicesAreIgnoredOnWelcome() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())

    gate.chooseMail()
    XCTAssertEqual(gate.route, .onboarding(.welcome))

    gate.chooseImport()
    XCTAssertEqual(gate.route, .onboarding(.welcome))
  }

  func testStartIsIgnoredOnceBringDataIsShown() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()

    gate.start()

    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  func testBackFromConnectMailReturnsToBringData() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()
    gate.chooseMail()

    gate.back()

    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  func testBackFromImportReturnsToBringData() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()
    gate.chooseImport()

    gate.back()

    XCTAssertEqual(gate.route, .onboarding(.bringData))
  }

  func testBackFromBringDataReturnsToWelcome() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())
    gate.start()

    gate.back()

    XCTAssertEqual(gate.route, .onboarding(.welcome))
  }

  func testBackFromWelcomeHasNowhereToGo() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore())

    gate.back()

    XCTAssertEqual(gate.route, .onboarding(.welcome))
  }

  // MARK: - Mail

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

  // MARK: - Data safety: skip stays skipped, and a returning user stays out

  /// The whole skip path, through the new steps: Welcome, Bring in your data,
  /// email, then Skip on the mail step. The next launch opens on the app.
  func testSkipAfterTheNewStepsStaysDismissedAcrossRelaunch() {
    let store = InMemoryKeyValueStore()
    let first = FirstRunGate(store: store)
    first.start()
    first.chooseMail()

    first.completeFirstRun()

    XCTAssertEqual(first.route, .main)
    XCTAssertEqual(FirstRunGate(store: store).route, .main)
  }

  /// A user who finished first run (by any exit) and then reaches a route that
  /// begins onboarding, from Settings or any other entry, is not sent back.
  func testAReturningUserIsNeverRoutedBackIntoOnboarding() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.completeFirstRun()

    gate.start()
    gate.chooseMail()
    gate.chooseImport()
    gate.back()
    gate.mailConnected()

    XCTAssertEqual(gate.route, .main)
    XCTAssertEqual(FirstRunGate(store: store).route, .main)
  }

  func testAReturningUserWithTheFlagSetOpensOnTheAppAtLaunch() {
    let store = InMemoryKeyValueStore()
    store.set(true, forKey: PreferenceKey.hasCompletedFirstRun)

    XCTAssertEqual(FirstRunGate(store: store).route, .main)
  }

  func testResetReturnsToWelcomeAndClearsTheFlag() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.completeFirstRun()

    gate.resetForTesting()

    XCTAssertEqual(gate.route, .onboarding(.welcome))
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
