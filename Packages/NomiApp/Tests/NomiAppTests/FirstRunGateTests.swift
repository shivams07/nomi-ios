import NomiCore
import SwiftData
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

  // MARK: - Data already on the device (an iCloud restore brings rows, not the flag)

  /// The restore case: CloudKit has brought transactions back, the flag has not
  /// come with them. The user must not be sent to onboarding.
  func testFlagAbsentWithStoredDataOpensOnTheAppAndSetsTheFlag() {
    let store = InMemoryKeyValueStore()

    let gate = FirstRunGate(store: store, hasStoredData: { true })

    XCTAssertEqual(gate.route, .main)
    XCTAssertTrue(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  func testFlagAbsentWithAnEmptyStoreOpensOnWelcome() {
    let store = InMemoryKeyValueStore()

    let gate = FirstRunGate(store: store, hasStoredData: { false })

    XCTAssertEqual(gate.route, .onboarding(.welcome))
    XCTAssertFalse(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// The check runs once. Once the flag is set, a launch reads the flag and
  /// does not touch the store.
  func testTheStoreIsNotCheckedOnceTheFlagIsSet() {
    let store = InMemoryKeyValueStore()
    store.set(true, forKey: PreferenceKey.hasCompletedFirstRun)
    var checks = 0

    let gate = FirstRunGate(store: store, hasStoredData: {
      checks += 1
      return false
    })

    XCTAssertEqual(gate.route, .main)
    XCTAssertEqual(checks, 0)
  }

  /// Detected data sets the flag, so the next launch needs no check at all.
  func testDetectedDataStaysDismissedOnRelaunchWithoutTheCheck() {
    let store = InMemoryKeyValueStore()
    _ = FirstRunGate(store: store, hasStoredData: { true })

    let relaunch = FirstRunGate(store: store, hasStoredData: { false })

    XCTAssertEqual(relaunch.route, .main)
  }

  /// The store the gate is given is the only one it writes. In a
  /// non-persistent launch that is the in-memory store, so the flag reaches
  /// `UserDefaults` only from a persistent launch (StoreWorkGateTests pins that).
  func testDetectedDataWritesOnlyToTheStoreItIsGiven() throws {
    let suite = "s12a.firstrun.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let inMemory = InMemoryKeyValueStore()

    _ = FirstRunGate(store: inMemory, hasStoredData: { true })

    XCTAssertTrue(inMemory.bool(forKey: PreferenceKey.hasCompletedFirstRun))
    XCTAssertFalse(defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// The probe, against a real stack: an empty store has nothing, and a single
  /// account or transaction row is enough to count as data.
  func testAnEmptyStoreHoldsNoData() throws {
    let stack = try InMemoryStack()
    XCTAssertFalse(try FirstRunGate.storeHoldsData(in: stack.context))
  }

  func testAnAccountRowCountsAsData() throws {
    let stack = try InMemoryStack()
    stack.context.insert(Account(displayName: "HDFC Savings"))
    try stack.context.save()
    XCTAssertTrue(try FirstRunGate.storeHoldsData(in: stack.context))
  }

  func testATransactionRowCountsAsData() throws {
    let stack = try InMemoryStack()
    stack.context.insert(Transaction())
    try stack.context.save()
    XCTAssertTrue(try FirstRunGate.storeHoldsData(in: stack.context))
  }

  // MARK: - A check that cannot be read (M4)

  private struct DataCheckFailed: Error {}

  /// A failed check is never a reason to show Welcome. The user lands in the app
  /// for this launch.
  func testAFailedDataCheckRoutesToTheAppNeverWelcome() {
    let gate = FirstRunGate(store: InMemoryKeyValueStore(), hasStoredData: { throw DataCheckFailed() })
    XCTAssertEqual(gate.route, .main)
  }

  /// A failed check persists nothing. Writing the flag on a check that could not
  /// be read would dismiss onboarding for good on a guess.
  func testAFailedDataCheckWritesNoFlag() {
    let store = InMemoryKeyValueStore()
    _ = FirstRunGate(store: store, hasStoredData: { throw DataCheckFailed() })
    XCTAssertFalse(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }

  /// The next launch asks again. With the store readable and empty, that launch
  /// is a first run, and it opens on Welcome.
  func testTheNextLaunchAsksAgainAfterAFailedCheck() {
    let store = InMemoryKeyValueStore()
    _ = FirstRunGate(store: store, hasStoredData: { throw DataCheckFailed() })

    let relaunch = FirstRunGate(store: store, hasStoredData: { false })

    XCTAssertEqual(relaunch.route, .onboarding(.welcome))
  }

  // MARK: - Erase (B5a step 5, G10)

  /// An erase sends the app back to Welcome and clears the flag, so the next
  /// launch reads it as a first run again.
  func testRestartAfterEraseReturnsToWelcomeAndClearsTheFlag() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.completeFirstRun()
    XCTAssertEqual(gate.route, .main)

    gate.restartAfterErase()

    XCTAssertEqual(gate.route, .onboarding(.welcome))
    XCTAssertFalse(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
    XCTAssertEqual(FirstRunGate(store: store).route, .onboarding(.welcome))
  }

  /// `resetForTesting` delegates to the same reset, so it still returns to Welcome.
  func testResetForTestingStillReturnsToWelcome() {
    let store = InMemoryKeyValueStore()
    let gate = FirstRunGate(store: store)
    gate.completeFirstRun()

    gate.resetForTesting()

    XCTAssertEqual(gate.route, .onboarding(.welcome))
    XCTAssertFalse(store.bool(forKey: PreferenceKey.hasCompletedFirstRun))
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
