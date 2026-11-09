#if canImport(UIKit)
import CoreGraphics
import Testing
import UIKit

@testable import NomiApp

/// SB2 (nomi-ios-statusbar-ruling): the overlay's two pure properties, that its
/// controller asks for light glyphs and never hides the bar, and that its window
/// takes no touches. Attaching and showing the overlay need a window scene, so
/// they are checked on the simulator instead. Whole file is UIKit-only, so it
/// does not run under macOS `swift test`.
@MainActor
@Suite("Status bar overlay")
struct StatusBarOverlayTests {

  @Test("the overlay controller asks for light glyphs and never hides the bar")
  func controllerIsLightAndNeverHides() {
    let controller = StatusBarOverlayController()
    #expect(controller.preferredStatusBarStyle == .lightContent)
    #expect(controller.prefersStatusBarHidden == false)
  }

  @Test("the overlay window passes every touch through")
  func windowPassesTouchesThrough() {
    let window = StatusBarOverlayWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(window.hitTest(CGPoint(x: 10, y: 10), with: nil) == nil)
  }
}
#endif
