import NomiCore
import XCTest

@testable import NomiApp

/// A `BudgetNotificationScheduling` that answers however the test needs and
/// records what reached it. The real one calls `UNUserNotificationCenter`, which
/// traps in a process with no bundle — its own doc comment says so.
private final class StubScheduler: BudgetNotificationScheduling, @unchecked Sendable {
  var authorizationAnswer: Result<Bool, Error> = .success(true)
  private(set) var requestCount = 0
  private(set) var scheduled: [BudgetAlert] = []

  @discardableResult
  func requestAuthorization() async throws -> Bool {
    requestCount += 1
    return try authorizationAnswer.get()
  }

  func schedule(_ alert: BudgetAlert) async throws {
    scheduled.append(alert)
  }
}

private struct StubError: Error {}

final class NotificationEnablePolicyTests: XCTestCase {

  /// §2.2: "A denied permission turns the toggle back off with visible copy — a
  /// toggle reading 'on' while the OS silently drops notifications is worse than
  /// one reading 'off'."
  func testDenialTurnsTheToggleBackOff() {
    let requested = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    let resolved = NotificationEnablePolicy.settings(after: requested, granted: false)
    XCTAssertFalse(resolved.budgetAlertsEnabled)
  }

  func testGrantLeavesTheToggleOn() {
    let requested = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    XCTAssertTrue(NotificationEnablePolicy.settings(after: requested, granted: true).budgetAlertsEnabled)
  }

  /// A failed request is not an unknown state to be optimistic about. "We could
  /// not establish that we may notify you" reads as "we may not".
  func testAFailedRequestIsTreatedAsDenial() {
    let requested = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    XCTAssertFalse(NotificationEnablePolicy.settings(after: requested, granted: nil).budgetAlertsEnabled)
  }

  /// Turning alerts *off* asks nobody for anything and must come back
  /// unchanged, including its threshold.
  func testDisablingIsUntouchedByThePolicy() {
    let requested = NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.75)
    let resolved = NotificationEnablePolicy.settings(after: requested, granted: false)
    XCTAssertEqual(resolved, requested)
  }

  func testOnlyOffToOnIsAnEnablingTransition() {
    let off = NotificationSettings(budgetAlertsEnabled: false, thresholdFraction: 0.9)
    let on = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)

    XCTAssertTrue(NotificationEnablePolicy.isEnablingTransition(from: off, to: on))
    XCTAssertFalse(NotificationEnablePolicy.isEnablingTransition(from: on, to: off))
    XCTAssertFalse(NotificationEnablePolicy.isEnablingTransition(from: on, to: on))
    XCTAssertFalse(NotificationEnablePolicy.isEnablingTransition(from: off, to: off))
  }

  /// Changing the threshold while already on must not re-prompt, and — more
  /// importantly — must not run §2.2's suppression pass again, which would
  /// silence a month's worth of crossings the user has not been told about.
  func testChangingTheThresholdWhileOnIsNotAnEnablingTransition() {
    let on = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    let tighter = NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.75)
    XCTAssertFalse(NotificationEnablePolicy.isEnablingTransition(from: on, to: tighter))
  }
}

@MainActor
final class NotificationSettingsStoreTests: XCTestCase {

  /// §2.18(3): "`SettingsScreen` takes it as a `Binding` ... Nothing persists
  /// it. U8 holds the source of truth and writes it."
  func testAFreshInstallHasAlertsOff() {
    let store = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: StubScheduler())
    XCTAssertFalse(store.settings.budgetAlertsEnabled)
  }

  func testSettingsSurviveARelaunch() {
    let preferences = InMemoryKeyValueStore()
    let first = NotificationSettingsStore(store: preferences, scheduler: StubScheduler())

    first.update(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.75))

    let second = NotificationSettingsStore(store: preferences, scheduler: StubScheduler())
    XCTAssertTrue(second.settings.budgetAlertsEnabled)
    XCTAssertEqual(second.settings.thresholdFraction, 0.75, accuracy: 0.0001)
  }

  func testCorruptStoredSettingsFallBackToOffRatherThanCrashing() {
    let preferences = InMemoryKeyValueStore()
    preferences.set(Data("not json".utf8), forKey: PreferenceKey.notificationSettings)

    let store = NotificationSettingsStore(store: preferences, scheduler: StubScheduler())

    XCTAssertFalse(store.settings.budgetAlertsEnabled)
  }

  func testTheBindingWritesThroughToTheStore() {
    let store = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: StubScheduler())
    store.binding.wrappedValue.thresholdFraction = 0.5
    XCTAssertEqual(store.settings.thresholdFraction, 0.5, accuracy: 0.0001)
  }

  func testEnablingRequestsPermissionAndKeepsTheToggleOnWhenGranted() async {
    let scheduler = StubScheduler()
    scheduler.authorizationAnswer = .success(true)
    let store = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: scheduler)

    await store.requestPermissionAndEnable(
      NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    )

    XCTAssertEqual(scheduler.requestCount, 1)
    XCTAssertTrue(store.settings.budgetAlertsEnabled)
  }

  /// Starts from a store that already believes alerts are on — the state a user
  /// is in after granting permission and later revoking it in iOS Settings —
  /// and asserts the denial is written through, not just held in memory.
  ///
  /// `requestPermissionAndEnable` is called directly rather than through
  /// `update`, which fires it in a detached `Task`: awaiting the method is
  /// deterministic, racing the task is not.
  func testEnablingWithADenialTurnsTheToggleBackOffAndPersistsThat() async {
    let preferences = InMemoryKeyValueStore()
    preferences.set(
      try? JSONEncoder().encode(NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)),
      forKey: PreferenceKey.notificationSettings
    )

    let scheduler = StubScheduler()
    scheduler.authorizationAnswer = .success(false)
    let store = NotificationSettingsStore(store: preferences, scheduler: scheduler)
    XCTAssertTrue(store.settings.budgetAlertsEnabled)

    await store.requestPermissionAndEnable(
      NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    )

    XCTAssertFalse(store.settings.budgetAlertsEnabled)
    XCTAssertFalse(
      NotificationSettingsStore(store: preferences, scheduler: StubScheduler())
        .settings.budgetAlertsEnabled
    )
  }

  func testAThrownAuthorizationRequestIsTreatedAsDenial() async {
    let scheduler = StubScheduler()
    scheduler.authorizationAnswer = .failure(StubError())
    let store = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: scheduler)

    await store.requestPermissionAndEnable(
      NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    )

    XCTAssertFalse(store.settings.budgetAlertsEnabled)
  }

  /// §2.2's opt-in rule runs only when permission was actually granted. Running
  /// it after a denial would write suppressed log rows for a month in which the
  /// user will never be notified, silencing the *next* month's first crossings
  /// if they later grant permission.
  func testTheSuppressionPassRunsOnGrantAndNotOnDenial() async {
    let granted = StubScheduler()
    granted.authorizationAnswer = .success(true)
    let grantedStore = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: granted)
    let grantedFlag = Flag()
    grantedStore.onAlertsEnabled = { grantedFlag.set() }

    await grantedStore.requestPermissionAndEnable(
      NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    )
    XCTAssertTrue(grantedFlag.isSet)

    let denied = StubScheduler()
    denied.authorizationAnswer = .success(false)
    let deniedStore = NotificationSettingsStore(store: InMemoryKeyValueStore(), scheduler: denied)
    let deniedFlag = Flag()
    deniedStore.onAlertsEnabled = { deniedFlag.set() }

    await deniedStore.requestPermissionAndEnable(
      NotificationSettings(budgetAlertsEnabled: true, thresholdFraction: 0.9)
    )
    XCTAssertFalse(deniedFlag.isSet)
  }
}

/// A reference box rather than a captured `var`. `onAlertsEnabled` is an
/// escaping async closure, and capturing a mutable local in one is the kind of
/// thing that compiles today and becomes an error under stricter concurrency
/// checking later.
private final class Flag: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false

  var isSet: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func set() {
    lock.lock()
    value = true
    lock.unlock()
  }
}
