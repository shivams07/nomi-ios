import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

final class NomiAppModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiAppModule.version.isEmpty)
  }

  // MARK: - B11: the fallback reports the mode it actually used

  /// Whichever branch it takes, the two halves of the answer have to agree:
  /// `.cloudKit` carries no reason, `.localOnly` carries a non-empty one, and
  /// the container that comes back works either way. A fallback that returned
  /// `.cloudKit` would put "iCloud sync: On" in front of a user whose data is
  /// going nowhere, which is worse than the silence this replaces.
  func testTheReportedModeAgreesWithItselfAndTheContainerWorks() throws {
    let storage = NomiModelContainer.makeWithLocalFallback()

    switch storage.mode {
    case .cloudKit:
      XCTAssertNil(storage.mode.reason)
      XCTAssertTrue(storage.mode.isSyncing)
    case .localOnly(let reason):
      XCTAssertFalse(reason.isEmpty, "a fallback that cannot say why is not much better than a print")
      XCTAssertFalse(storage.mode.isSyncing)
    }

    let context = ModelContext(storage.container)
    let id = UUID()
    context.insert(Rule(id: id, pattern: "STORAGE*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate { $0.id == id })).count, 1,
      "falling back loses sync, not data")
  }

  /// `swift test` has no iCloud entitlement, so the CloudKit container cannot
  /// construct here and this is the fallback path end to end — the one
  /// environment in this project where B11's branch is actually reachable.
  ///
  /// If this ever goes red it is worth reading rather than deleting: it would
  /// mean the runner gained an entitlement, or that `makeCloudKit()` stopped
  /// failing where we assumed it does.
  func testTheTestRunnerHasNoEntitlementSoItFallsBackAndSaysWhy() {
    let storage = NomiModelContainer.makeWithLocalFallback()

    guard case .localOnly(let reason) = storage.mode else {
      return XCTFail("expected the local fallback under swift test, got \(storage.mode)")
    }
    XCTAssertFalse(reason.isEmpty)
  }
}
