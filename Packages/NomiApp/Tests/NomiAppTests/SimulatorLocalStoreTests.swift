import NomiCore
import XCTest

@testable import NomiApp

/// SIM1: an unsigned simulator build must open the local store, not CloudKit.
///
/// The decision is `NomiModelContainer.simulatorLocalOnlyReason`, a pure
/// function over two booleans. Every test here passes those booleans in, so
/// the four combinations are covered without a host that is a simulator.
///
/// **No test constructs a real CloudKit container.** Constructing one under
/// `swift test` traps the process (see `NomiAppModuleTests`). The integration
/// tests inject a counting maker: in the local-store cases it must never be
/// called, and in the CloudKit cases a local stand-in is used, so no CloudKit
/// object is created.
final class SimulatorLocalStoreTests: XCTestCase {

  private let reason = "Simulator build without iCloud entitlement"

  // MARK: - The four combinations of the pure decision

  /// The case SIM1 exists for: an unsigned simulator Debug build with no
  /// escape hatch uses the local store, and says why.
  func testSimulatorDebugWithoutForceChoosesTheLocalStore() {
    XCTAssertEqual(
      NomiModelContainer.simulatorLocalOnlyReason(
        isSimulatorDebugBuild: true, forceCloudKit: false),
      reason)
  }

  /// `NOMI_FORCE_CLOUDKIT=1` restores CloudKit in a simulator Debug build.
  func testSimulatorDebugWithForceKeepsCloudKit() {
    XCTAssertNil(
      NomiModelContainer.simulatorLocalOnlyReason(
        isSimulatorDebugBuild: true, forceCloudKit: true))
  }

  /// A device or Release build selects CloudKit exactly as before.
  func testDeviceOrReleaseWithoutForceKeepsCloudKit() {
    XCTAssertNil(
      NomiModelContainer.simulatorLocalOnlyReason(
        isSimulatorDebugBuild: false, forceCloudKit: false))
  }

  /// The escape hatch is inert off the simulator, so setting it on a device
  /// build cannot change which store opens.
  func testDeviceOrReleaseWithForceKeepsCloudKit() {
    XCTAssertNil(
      NomiModelContainer.simulatorLocalOnlyReason(
        isSimulatorDebugBuild: false, forceCloudKit: true))
  }

  // MARK: - The compile-time guard

  /// The two constants that feed the defaults must match the compile
  /// condition of this configuration. Under any configuration other than a
  /// simulator Debug build, both must be `false`, so device and Release code
  /// never reads the environment.
  func testTheCompileGuardsMatchThisBuildConfiguration() {
    #if DEBUG && targetEnvironment(simulator)
      XCTAssertTrue(NomiModelContainer.currentBuildIsSimulatorDebug)
    #else
      XCTAssertFalse(NomiModelContainer.currentBuildIsSimulatorDebug)
      XCTAssertFalse(NomiModelContainer.currentForceCloudKitRequested)
    #endif
  }

  // MARK: - Through the fallback, with the CloudKit maker counted

  /// On a simulator Debug build without the escape hatch the CloudKit maker
  /// is never called. That is the whole point: the mirroring delegate traps
  /// later, asynchronously, after the maker has already returned.
  func testSimulatorDebugOpensTheLocalStoreWithoutCallingTheCloudKitMaker() throws {
    var makerCalls = 0
    let storage = NomiModelContainer.makeWithLocalFallback(
      cloudKit: {
        makerCalls += 1
        return try NomiModelContainer.makeLocal()
      },
      isSimulatorDebugBuild: true, forceCloudKit: false)

    XCTAssertEqual(makerCalls, 0, "the CloudKit maker must not run on an unsigned simulator build")
    XCTAssertEqual(storage.mode, .localOnly(reason: reason))
    XCTAssertFalse(storage.mode.isSyncing)
  }

  /// The forced case goes down the CloudKit path. The stand-in is a local
  /// maker, so the test checks only which branch was taken.
  func testSimulatorDebugWithForceCallsTheCloudKitMakerAndReportsCloudKit() throws {
    var makerCalls = 0
    let storage = NomiModelContainer.makeWithLocalFallback(
      cloudKit: {
        makerCalls += 1
        return try NomiModelContainer.makeLocal()
      },
      isSimulatorDebugBuild: true, forceCloudKit: true)

    XCTAssertEqual(makerCalls, 1)
    XCTAssertEqual(storage.mode, .cloudKit)
  }

  /// The device path is unchanged: the maker runs once and its success is
  /// reported as CloudKit.
  func testDeviceBuildCallsTheCloudKitMakerAndReportsCloudKit() throws {
    var makerCalls = 0
    let storage = NomiModelContainer.makeWithLocalFallback(
      cloudKit: {
        makerCalls += 1
        return try NomiModelContainer.makeLocal()
      },
      isSimulatorDebugBuild: false, forceCloudKit: false)

    XCTAssertEqual(makerCalls, 1)
    XCTAssertEqual(storage.mode, .cloudKit)
  }
}
