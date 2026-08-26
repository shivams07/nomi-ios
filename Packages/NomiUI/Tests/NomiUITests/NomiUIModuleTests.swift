import XCTest
@testable import NomiUI

final class NomiUIModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiUIModule.version.isEmpty)
  }
}
