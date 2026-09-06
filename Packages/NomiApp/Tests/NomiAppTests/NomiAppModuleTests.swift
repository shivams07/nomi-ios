import NomiCore
import SwiftData
import XCTest

@testable import NomiApp

final class NomiAppModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiAppModule.version.isEmpty)
  }

  // MARK: - B11: the fallback reports the mode it actually used

  /// **Nothing here constructs a real CloudKit container**, and that is not
  /// squeamishness: the first version of these tests called
  /// `makeWithLocalFallback()` with its default maker, and the CloudKit
  /// mirroring delegate trapped the whole test process on the runner (signal
  /// 5, CI run 33994342474) after container construction had already returned
  /// successfully. The maker is injected instead, so both branches are
  /// reachable without CloudKit being involved at all.
  private struct NoCloudKit: Error {}

  /// The failure branch, end to end: a maker that throws must produce
  /// `.localOnly`, must carry a reason a user could read out, and must still
  /// hand back a container that works — falling back loses sync, not data.
  func testAFailingCloudKitMakerFallsBackToAWorkingLocalStoreAndSaysWhy() throws {
    let storage = NomiModelContainer.makeWithLocalFallback(cloudKit: { throw NoCloudKit() })

    guard case .localOnly(let reason) = storage.mode else {
      return XCTFail("expected the local fallback when the maker throws, got \(storage.mode)")
    }
    XCTAssertFalse(reason.isEmpty, "a fallback that cannot say why is not much better than a print")
    XCTAssertFalse(storage.mode.isSyncing)

    let context = ModelContext(storage.container)
    let id = UUID()
    context.insert(Rule(id: id, pattern: "STORAGE*", categoryID: UUID()))
    try context.save()
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<Rule>(predicate: #Predicate { $0.id == id })).count, 1,
      "falling back loses sync, not data")
  }

  /// The success branch. The container handed back is a local one — this test
  /// is about the *reporting*, not about reaching iCloud — but the point holds
  /// either way: a maker that returns without throwing must be reported as
  /// `.cloudKit` and must carry no reason, or Settings would show a failure
  /// caption to a user who has none.
  func testAMakerThatSucceedsIsReportedAsCloudKitWithNoReason() throws {
    let storage = NomiModelContainer.makeWithLocalFallback(cloudKit: NomiModelContainer.makeLocal)

    XCTAssertEqual(storage.mode, .cloudKit)
    XCTAssertNil(storage.mode.reason)
    XCTAssertTrue(storage.mode.isSyncing)
  }

  /// The local store is what the fallback lands on, so it has to be able to
  /// open the whole schema on its own. If this goes red the fallback is not a
  /// fallback.
  func testTheLocalContainerOpensTheWholeSchema() throws {
    XCTAssertNoThrow(try NomiModelContainer.makeLocal())
  }
}
