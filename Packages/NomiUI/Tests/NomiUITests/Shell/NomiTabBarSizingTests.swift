import SwiftUI
import Testing
@testable import NomiUI

// clt-harness: include

/// TB1's Dynamic Type rule for the tab bar, pinned as values. The label widths are
/// the iOS rendered widths from `NomiTabBarLayoutTests` (points, Home, Ledger,
/// Insights, Accounts). Sizes above `xLarge` are the uncapped widths, measured
/// with the cap removed, so the claims about AX sizes are about what the cap stops.
/// Slot widths include the capsule padding (`capsuleLabelPadding`, D10).
@Suite("Tab bar Dynamic Type")
struct NomiTabBarSizingTests {
  private static let everySize: [DynamicTypeSize] = [
    .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
  ]

  private static let measured: [(size: DynamicTypeSize, widths: [CGFloat])] = [
    (.large, [31.3, 37.3, 41.3, 50.0]),
    (.xLarge, [42.7, 50.7, 56.7, 68.0]),
    (.xxLarge, [45.3, 54.0, 60.3, 72.7]),
    (.xxxLarge, [51.0, 60.7, 67.7, 81.7]),
    (.accessibility1, [56.7, 67.3, 75.3, 90.7]),
    (.accessibility2, [65.0, 77.7, 86.7, 104.3]),
    (.accessibility3, [79.3, 94.3, 105.3, 127.0]),
    (.accessibility4, [93.3, 111.3, 124.0, 149.7]),
    (.accessibility5, [110.3, 131.3, 146.7, 177.0]),
  ]

  /// RootView's side margin on the bar is 24 pt, from `TabBarInsetHeight.sideMargin`.
  private static let budget375 = NomiTabBarSizing.tabSpaceBudget(screenWidth: 375, sideMargin: 24)
  private static let budget440 = NomiTabBarSizing.tabSpaceBudget(screenWidth: 440, sideMargin: 24)

  private static func widths(at size: DynamicTypeSize) -> [CGFloat] {
    measured.first { $0.size == size }?.widths ?? []
  }

  @Test("the cap is xLarge, the largest size whose padded slots fit 375 pt")
  func capIsXLarge() {
    #expect(NomiTabBarSizing.maximumTypeSize == .xLarge)
  }

  @Test("the capsule padding is 4 pt on each side of the label")
  func capsulePaddingIsFourPoints() {
    #expect(NomiTabBarSizing.capsuleLabelPadding == 4)
  }

  @Test("every slot leaves at least the padding on each side of its label, up to the cap")
  func everySlotPadsEachLabel() {
    for entry in Self.measured where entry.size <= NomiTabBarSizing.maximumTypeSize {
      for width in entry.widths {
        let slot = NomiTabBarSizing.slotWidth(forLabelWidth: width)
        #expect(slot - width >= 2 * NomiTabBarSizing.capsuleLabelPadding - 0.001, "label \(width) pt in slot \(slot) pt, size \(entry.size)")
      }
    }
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

  @Test("every size up to the cap fits its four slots at 375 pt")
  func labelsFitAtNarrowWidthUpToCap() {
    for entry in Self.measured where entry.size <= NomiTabBarSizing.maximumTypeSize {
      #expect(
        NomiTabBarSizing.labelsFitOneLine(labelWidths: entry.widths, budget: Self.budget375),
        "labels should fit at 375 pt, size \(entry.size)"
      )
    }
  }

  @Test("xxxLarge does not fit at 375 pt: its padded slots add to 293.1 pt against 259 pt")
  func xxxLargeDoesNotFitAtNarrowWidth() {
    #expect(
      !NomiTabBarSizing.labelsFitOneLine(
        labelWidths: Self.widths(at: .xxxLarge),
        budget: Self.budget375
      )
    )
  }

  @Test("AX1 fits at 440 pt, so 375 pt is the width that sets the cap")
  func axOneFitsAtWideWidth() {
    #expect(
      NomiTabBarSizing.labelsFitOneLine(
        labelWidths: Self.widths(at: .accessibility1),
        budget: Self.budget440
      )
    )
  }

  @Test("AX2 does not fit at 440 pt either: the cap is needed at the wide width too")
  func axTwoDoesNotFitAtWideWidth() {
    #expect(
      !NomiTabBarSizing.labelsFitOneLine(
        labelWidths: Self.widths(at: .accessibility2),
        budget: Self.budget440
      )
    )
  }

  @Test("a tab slot is never narrower than the artboard's 56 pt")
  func slotNeverNarrowerThanArtboard() {
    #expect(NomiTabBarSizing.slotWidth(forLabelWidth: 10) == 56)
    #expect(NomiTabBarSizing.slotWidth(forLabelWidth: 40) == 56)
  }

  @Test("a slot is its label plus the padding on each side, once wider than 56 pt")
  func slotWidensByThePadding() {
    // Large Accounts is 50.0 pt, so its selected capsule is 58 pt (the artboard's 56 to 58 at Large).
    #expect(abs(NomiTabBarSizing.slotWidth(forLabelWidth: 50.0) - 58) < 0.001)
    // xLarge Accounts is 68.0 pt, so its capsule is 76 pt.
    #expect(abs(NomiTabBarSizing.slotWidth(forLabelWidth: 68.0) - 76) < 0.001)
  }

  @Test("the tap target stays at least 44 pt on each tab")
  func tapTargetStaysAtLeast44() {
    #expect(NomiTabBarSizing.slotMinWidth >= 44)
  }
}
