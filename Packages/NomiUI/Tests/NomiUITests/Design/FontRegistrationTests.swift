import XCTest
@testable import NomiUI

final class FontRegistrationTests: XCTestCase {
  /// Every bundled file registers, and its PostScript name (the file name minus
  /// `.otf`) resolves to a font. Inter Medium and SemiBold are not bundled yet
  /// (Q2), so they are not in this list.
  func testEveryBundledFontRegistersAndResolvesByPostScriptName() {
    NomiFont.registerIfNeeded()

    XCTAssertFalse(NomiFont.bundledFileNames.isEmpty)
    for fileName in NomiFont.bundledFileNames {
      let postScriptName = String(fileName.dropLast(".otf".count))
      let font = NomiPlatformFont(name: postScriptName, size: 16)
      XCTAssertNotNil(font, "\(postScriptName) did not resolve to a registered font")
      XCTAssertEqual(font?.fontName, postScriptName)
    }
  }

  /// The one face the app's live copy depends on right now resolves by name.
  func testInterRegularResolvesByName() {
    NomiFont.registerIfNeeded()

    XCTAssertNotNil(NomiPlatformFont(name: NomiFont.interRegular, size: 16))
  }

  /// U18: a second `registerIfNeeded()` in the same process re-registers
  /// nothing already registered. `CTFontManagerRegisterFontsForURL` returns
  /// false the second time around, and that must not trip the `assert`. If
  /// the guard regresses, this traps the test process rather than failing
  /// cleanly, which is still a signal: the process crashing is the bug.
  func testRegisterIfNeededCalledTwiceInOneProcessDoesNotAssert() {
    NomiFont.registerIfNeeded()
    NomiFont.registerIfNeeded()

    XCTAssertNotNil(NomiPlatformFont(name: NomiFont.interRegular, size: 16))
  }
}
