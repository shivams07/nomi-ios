import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// TB1's Dynamic Type rule for the tab bar, pinned as values. The label widths are
/// CoreText measurements of the bundled Inter Medium at 10.5 pt scaled by the
/// caption2 steps (11 pt at Large), in the order Home, Ledger, Insights, Accounts.
/// They are estimates from the HIG steps until a simulator run confirms them.
@Suite("Tab bar Dynamic Type")
struct NomiTabBarSizingTests {
  private static let everySize: [DynamicTypeSize] = [
    .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
  ]

  private static let measured: [(size: DynamicTypeSize, widths: [CGFloat])] = [
    (.large, [29.7, 35.3, 39.4, 47.6]),
    (.xLarge, [35.0, 41.8, 46.6, 56.2]),
    (.xxLarge, [37.7, 45.0, 50.2, 60.6]),
    (.xxxLarge, [40.4, 48.2, 53.8, 64.9]),
    (.accessibility1, [48.5, 57.8, 64.5, 77.9]),
    (.accessibility2, [59.3, 70.7, 78.9, 95.2]),
  ]

  /// RootView's side margin on the bar is 24 pt, from `TabBarInsetHeight.sideMargin`.
  private static let budget375 = NomiTabBarSizing.tabSpaceBudget(screenWidth: 375, sideMargin: 24)
  private static let budget440 = NomiTabBarSizing.tabSpaceBudget(screenWidth: 440, sideMargin: 24)

  private static func widths(at size: DynamicTypeSize) -> [CGFloat] {
    measured.first { $0.size == size }?.widths ?? []
  }

  @Test("the cap is xxxLarge, the largest non-accessibility size")
  func capIsXXXLarge() {
    #expect(NomiTabBarSizing.maximumTypeSize == .xxxLarge)
  }

  @Test("the cap sits below every accessibility size, so AX sizes are the ones it clamps")
  func capIsBelowEveryAccessibilitySize() {
    #expect(NomiTabBarSizing.maximumTypeSize < .accessibility1)
  }

  @Test("sizes at or below the cap are unchanged")
  func sizesAtOrBelowCapAreUnchanged() {
    for size in Self.everySize where size <= NomiTabBarSizing.maximumTypeSize {
      #expect(NomiTabBarSizing.effectiveTypeSize(size) == size)
    }
  }

  @Test("sizes above the cap draw as the cap")
  func sizesAboveCapDrawAsCap() {
    for size in Self.everySize where size > NomiTabBarSizing.maximumTypeSize {
      #expect(NomiTabBarSizing.effectiveTypeSize(size) == NomiTabBarSizing.maximumTypeSize)
    }
  }

  @Test("the tab budget at 375 pt is 259 and at 440 pt is 324")
  func budgetAtNarrowAndWide() {
    #expect(abs(Self.budget375 - 259) < 0.001)
    #expect(abs(Self.budget440 - 324) < 0.001)
  }

  @Test("every size up to the cap keeps all four labels on one line at 375 pt")
  func labelsFitAtNarrowWidthUpToCap() {
    for entry in Self.measured where entry.size <= NomiTabBarSizing.maximumTypeSize {
      #expect(
        NomiTabBarSizing.labelsFitOneLine(labelWidths: entry.widths, budget: Self.budget375),
        "labels should fit at 375 pt, size \(entry.size)"
      )
    }
  }

  @Test("the cap is the largest size whose labels fit at 375 pt: AX1 does not")
  func axOneDoesNotFitAtNarrowWidth() {
    #expect(
      !NomiTabBarSizing.labelsFitOneLine(
        labelWidths: Self.widths(at: .accessibility1),
        budget: Self.budget375
      )
    )
  }

  @Test("AX1 would fit at 440 pt, so 375 pt is the width that sets the cap")
  func axOneFitsAtWideWidth() {
    #expect(
      NomiTabBarSizing.labelsFitOneLine(
        labelWidths: Self.widths(at: .accessibility1),
        budget: Self.budget440
      )
    )
  }

  @Test("a tab slot is never narrower than the artboard's 56 pt")
  func slotNeverNarrowerThanArtboard() {
    #expect(NomiTabBarSizing.slotWidth(forLabelWidth: 10) == 56)
    #expect(NomiTabBarSizing.slotWidth(forLabelWidth: 64.9) == 64.9)
  }

  @Test("the tap target stays at least 44 pt on each tab")
  func tapTargetStaysAtLeast44() {
    #expect(NomiTabBarSizing.slotMinWidth >= 44)
  }
}
