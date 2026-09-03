import XCTest

@testable import NomiApp

/// `ui-tabbar-safe-area`: the bar has no fixed height anywhere in this app —
/// it's measured via a `PreferenceKey` and reserved through
/// `TabBarInsetHeight.reserved(barHeight:)`, the one seam `RootView` actually
/// calls to size its `.safeAreaInset`. These assertions derive the expected
/// margin from the function itself (`reserved(barHeight: 0)`) rather than a
/// literal, so this can't pass by agreeing with a hardcoded number that
/// happens to match production code by coincidence — the failure mode this
/// unit exists to remove.
final class TabBarLayoutTests: XCTestCase {
  func testInsetIsNeverSmallerThanTheMeasuredBarHeight() {
    XCTAssertGreaterThanOrEqual(TabBarInsetHeight.reserved(barHeight: 64), 64)
  }

  func testInsetAddsAFixedMarginOnTopOfTheMeasuredBarHeight() {
    let margin = TabBarInsetHeight.reserved(barHeight: 0)
    XCTAssertEqual(TabBarInsetHeight.reserved(barHeight: 64), 64 + margin)
    XCTAssertEqual(TabBarInsetHeight.reserved(barHeight: 96), 96 + margin)
  }

  func testInsetScalesOneToOneWithTheMeasuredBarHeight() {
    // At larger Dynamic Type sizes the bar's label grows, so its measured
    // height grows too -- the inset must track the delta exactly, not apply
    // its own separate scaling or clamp.
    let delta = TabBarInsetHeight.reserved(barHeight: 96) - TabBarInsetHeight.reserved(barHeight: 64)
    XCTAssertEqual(delta, 32, accuracy: 0.001)
  }

  func testZeroMeasuredHeightStillReservesTheMargin() {
    // Before the GeometryReader has ever reported a size (first frame,
    // preference default), the inset must not collapse to zero.
    XCTAssertGreaterThan(TabBarInsetHeight.reserved(barHeight: 0), 0)
  }
}
