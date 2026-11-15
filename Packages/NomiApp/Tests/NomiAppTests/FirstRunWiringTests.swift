import Foundation
import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

/// M7: the gate that `AppEnvironment` builds performs the data-presence check.
///
/// `FirstRunGateTests` injects its own probe, so a wiring that forgot to pass the
/// check would pass every one of them. This test builds the real wiring, through
/// the same factory `AppServices.shared` uses, over a persistent store that
/// already holds an account, with no first-run flag. Only the route can show
/// that the check ran.
///
/// `@MainActor` because `AppServices` is. Each `UserDefaults` is a fresh suite,
/// removed in tearDown, so the test runner's domain is never written.
@MainActor
final class FirstRunWiringTests: XCTestCase {
  private var directory: URL!
  private var suiteNames: [String] = []
  /// Every environment a test makes, held to the end of the test. A
  /// `ModelContext` does not keep its container alive.
  private var keepAlive: [AnyObject] = []

  private struct Unavailable: Error {}

  private struct InertAccountProbe: CloudKitAccountProbing {
    func pauseReason() async -> SyncPauseReason? { nil }
    func accountChanges() -> AsyncStream<Void> {
      AsyncStream<Void> { continuation in continuation.finish() }
    }
  }

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    keepAlive = []
    for name in suiteNames {
      UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
    try? FileManager.default.removeItem(at: directory)
  }

  private func makeDefaults() throws -> UserDefaults {
    let name = UUID().uuidString
    suiteNames.append(name)
    return try XCTUnwrap(UserDefaults(suiteName: name))
  }

  /// A persistent source over `storeURL`, opened the way production opens the
  /// local store. CloudKit always throws here.
  private func makeSource(storeURL: URL, recovery: UserDefaults) -> StoreWorkEnvironment {
    let scratch: URL = directory
    let source = StoreWorkEnvironment(
      open: {
        NomiModelContainer.makeWithLocalFallback(
          cloudKit: { throw Unavailable() },
          local: { try NomiModelContainer.makeLocal(at: storeURL) },
          storeURL: storeURL,
          recoveryDefaults: recovery,
          scratchDirectory: scratch)
      },
      protectedDataAvailable: { true })
    keepAlive.append(source)
    return source
  }

  /// The app's wiring, built by the factory `AppServices.shared` is built by.
  private func makeWiring(_ source: StoreWorkEnvironment, defaults: UserDefaults) -> AppEnvironment {
    let environment = AppServices.make(
      environment: source,
      defaults: defaults,
      credentials: MemoryCredentialStore(),
      mailFetcher: OrderRecordingMailFetcher(),
      scheduler: NoopNotificationScheduler(),
      accountProbe: InertAccountProbe())
    keepAlive.append(environment)
    return environment
  }

  /// A store that already holds an account, but a preferences store with no
  /// first-run flag (what an iCloud restore looks like on a new install). The
  /// environment the app builds must read the store and open on the app.
  func testTheWiringsGateReadsTheStoreBeforeShowingWelcome() throws {
    let storeURL = directory.appendingPathComponent("default.store")
    do {
      // Seed, then let this container go before the wiring opens the same file.
      let seeded = try NomiModelContainer.makeLocal(at: storeURL)
      seeded.mainContext.insert(Account(displayName: "HDFC Savings"))
      try seeded.mainContext.save()
    }
    let defaults = try makeDefaults()
    let recovery = try makeDefaults()

    let wiring = makeWiring(makeSource(storeURL: storeURL, recovery: recovery), defaults: defaults)

    XCTAssertEqual(
      wiring.firstRun.route, .main,
      "the environment's gate must check the store; a flagless install with rows opened on Welcome")
    XCTAssertTrue(defaults.bool(forKey: PreferenceKey.hasCompletedFirstRun))
  }
}
