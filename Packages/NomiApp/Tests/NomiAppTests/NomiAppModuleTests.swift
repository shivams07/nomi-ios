import XCTest
@testable import NomiApp

final class NomiAppModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiAppModule.version.isEmpty)
  }
}
