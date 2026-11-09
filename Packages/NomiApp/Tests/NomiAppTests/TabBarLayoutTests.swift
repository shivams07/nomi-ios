import NomiUI
import SwiftUI
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

  func testReservedMarginIsTheArtboardBottomOffset() {
    // The bar floats 22 pt above the bottom edge on the artboards, so the
    // reserved space must cover that offset as well as the bar.
    XCTAssertEqual(TabBarInsetHeight.reserved(barHeight: 0), 22, accuracy: 0.001)
    XCTAssertEqual(TabBarInsetHeight.reserved(barHeight: 64), 86, accuracy: 0.001)
  }

  /// TB1 with the D10 capsule padding: at the cap (xLarge) the four slots, each the
  /// label plus 4 pt either side, fit 375 pt with RootView's margins. The widths are the
  /// device's xLarge label widths from `NomiTabBarLayoutTests`.
  func testSlotsFit375AtCapWithPadding() {
    let budget = NomiTabBarSizing.tabSpaceBudget(screenWidth: 375, sideMargin: TabBarInsetHeight.sideMargin)
    XCTAssertEqual(NomiTabBarSizing.maximumTypeSize, .xLarge)
    XCTAssertTrue(NomiTabBarSizing.labelsFitOneLine(labelWidths: [42.7, 50.7, 56.7, 68.0], budget: budget))
    // The next size up does not fit with the padding, so the cap is the largest that does.
    XCTAssertFalse(NomiTabBarSizing.labelsFitOneLine(labelWidths: [45.3, 54.0, 60.3, 72.7], budget: budget))
  }

  func testZeroMeasuredHeightStillReservesTheMargin() {
    // Before the GeometryReader has ever reported a size (first frame,
    // preference default), the inset must not collapse to zero.
    XCTAssertGreaterThan(TabBarInsetHeight.reserved(barHeight: 0), 0)
  }
}
