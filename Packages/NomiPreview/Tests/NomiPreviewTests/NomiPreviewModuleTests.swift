import XCTest
@testable import NomiPreview

final class NomiPreviewModuleTests: XCTestCase {
  func testVersionIsSet() {
    XCTAssertFalse(NomiPreviewModule.version.isEmpty)
  }
}
