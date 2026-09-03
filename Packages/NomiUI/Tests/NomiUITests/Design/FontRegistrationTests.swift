import XCTest
@testable import NomiUI

final class FontRegistrationTests: XCTestCase {
  func testAllFourFontsRegisterAndResolveByPostScriptName() {
    NomiFont.registerIfNeeded()

    let constants = [
      NomiFont.montserratMedium,
      NomiFont.montserratSemiBold,
      NomiFont.montserratBold,
      NomiFont.interRegular,
    ]

    for constant in constants {
      let font = NomiPlatformFont(name: constant, size: 16)
      XCTAssertNotNil(font, "\(constant) did not resolve to a registered font")
      XCTAssertEqual(font?.fontName, constant)
    }
  }

  func testFourConstantsAreDistinctPostScriptNames() {
    let constants = [
      NomiFont.montserratMedium,
      NomiFont.montserratSemiBold,
      NomiFont.montserratBold,
      NomiFont.interRegular,
    ]

    XCTAssertEqual(Set(constants).count, constants.count)
  }
}
