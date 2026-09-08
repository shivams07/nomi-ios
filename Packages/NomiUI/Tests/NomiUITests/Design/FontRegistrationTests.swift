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

  /// U18: a second `registerIfNeeded()` in the same process re-registers
  /// nothing already registered — `CTFontManagerRegisterFontsForURL` returns
  /// false the second time around, and that must not trip the `assert`. If
  /// the guard regresses, this traps the test process rather than failing
  /// cleanly, which is still a signal: the process crashing is the bug.
  func testRegisterIfNeededCalledTwiceInOneProcessDoesNotAssert() {
    NomiFont.registerIfNeeded()
    NomiFont.registerIfNeeded()

    XCTAssertNotNil(NomiPlatformFont(name: NomiFont.montserratMedium, size: 16))
  }
}
