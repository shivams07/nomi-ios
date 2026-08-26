import XCTest
@testable import NomiIngest

final class NomiIngestModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiIngestModule.version.isEmpty)
  }
}
