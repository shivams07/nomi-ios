import XCTest
@testable import NomiCore

final class NomiCoreModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiCoreModule.version.isEmpty)
  }
}
