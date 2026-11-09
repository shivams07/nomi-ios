#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import NomiUI

/// TB1 on UIKit: the real `NomiTabBar` hosted in a `UIHostingController` at the
/// phone width, with RootView's margins (24 pt sides, 22 pt bottom), the registered
/// Inter fonts, and the UIKit content-size trait set per case. Every number is read
/// from rendered frames, not estimated.
///
/// Frames come from `NomiTabBarFramesKey`, which the bar publishes in global
/// coordinates. The hosted accessibility tree does not expose SwiftUI's labels in a
/// test host, so it is not used.
///
/// This file is iOS-only. `swift test` on macOS compiles it out. Run it with
/// `xcodebuild test -scheme NomiUI -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max'`.
@MainActor
final class NomiTabBarLayoutTests: XCTestCase {
  override class func setUp() {
    super.setUp()
    NomiFont.registerIfNeeded()
  }

  private static let tabTitles = ["Home", "Ledger", "Insights", "Accounts"]
  private static let widths: [CGFloat] = [375, 390, 402, 440]
  private static let checkedSizes: [(name: String, category: UIContentSizeCategory)] = [
    ("large", .large),
    ("xLarge", .extraLarge),
    ("xxLarge", .extraExtraLarge),
    ("xxxLarge", .extraExtraExtraLarge),
    ("accessibilityMedium", .accessibilityMedium),
    ("accessibilityXXXLarge", .accessibilityExtraExtraExtraLarge),
  ]
  /// Every size, for the width table. Widths do not depend on the screen width.
  private static let tableSizes: [(name: String, category: UIContentSizeCategory)] = [
    ("large", .large),
    ("xLarge", .extraLarge),
    ("xxLarge", .extraExtraLarge),
    ("xxxLarge", .extraExtraExtraLarge),
    ("accessibilityMedium", .accessibilityMedium),
    ("accessibilityLarge", .accessibilityLarge),
    ("accessibilityExtraLarge", .accessibilityExtraLarge),
    ("accessibilityExtraExtraLarge", .accessibilityExtraExtraLarge),
    ("accessibilityXXXLarge", .accessibilityExtraExtraExtraLarge),
  ]
  /// The category at `NomiTabBarSizing.maximumTypeSize`. Sizes above it must measure as this one.
  private static let capCategory: UIContentSizeCategory = .extraLarge

  // MARK: - Tests

  func testEveryTabLabelIsOneLineAtEveryCheckedSizeAndWidth() {
    for width in Self.widths {
      for size in Self.checkedSizes {
        let measured = measure(width: width, category: size.category)
        let oneLine = oneLineHeight(size.category)
        for title in Self.tabTitles {
          guard let label = measured.frame("label:\(title)") else {
            XCTFail("no label frame for \(title) at \(size.name), \(width) pt")
            continue
          }
          XCTAssertLessThan(
            label.height, 1.5 * oneLine,
            "\(title) wraps at \(size.name), \(width) pt: label \(label.height) pt, one line is \(oneLine) pt"
          )
        }
      }
    }
  }

  /// At default size the bar is the artboard's 64 pt at every width. Above it the bar
  /// grows only as far as its capsule, and never past the bound (D10, vertical).
  func testBarHeightIsSixtyFourAtLargeAndBoundedAboveAtEveryWidth() {
    for width in Self.widths {
      for size in Self.checkedSizes {
        let measured = measure(width: width, category: size.category)
        let bar = measured.bar
        XCTAssertGreaterThanOrEqual(bar.height, 64 - 0.5, "bar below 64 at \(size.name), \(width) pt")
        XCTAssertLessThanOrEqual(
          bar.height, NomiTabBarSizing.barHeightBound + 0.5,
          "bar is \(bar.height) pt at \(size.name), \(width) pt, above the \(NomiTabBarSizing.barHeightBound) pt bound"
        )
        if size.category == .large {
          XCTAssertEqual(bar.height, 64, accuracy: 0.5, "bar is \(bar.height) pt at Large, \(width) pt")
        }
        // The bar is exactly the rule applied to its selected capsule.
        if let capsule = measured.frame("slot:Home") {
          XCTAssertEqual(
            bar.height, NomiTabBarSizing.barHeight(capsuleHeight: capsule.height), accuracy: 0.5,
            "bar \(bar.height) pt does not follow its capsule \(capsule.height) pt at \(size.name), \(width) pt"
          )
        }
      }
    }
  }

  /// The selected capsule holds its label's full frame, vertically and horizontally,
  /// with the 4 pt padding on every side, for every tab, at Large, xLarge and AX-XXXL,
  /// at each width. Without the vertical padding the label sits on or past the bottom edge.
  func testCapsuleContainsEveryLabelsFullFrameWithPaddingOnAllSides() {
    let padding = NomiTabBarSizing.capsuleLabelPadding - 0.5
    let checked: [UIContentSizeCategory] = [.large, .extraLarge, .accessibilityExtraExtraExtraLarge]
    for selected in Self.tabTitles {
      for width in Self.widths {
        for category in checked {
          let measured = measure(width: width, category: category, selectedID: selected.lowercased())
          guard let label = measured.frame("label:\(selected)"), let slot = measured.frame("slot:\(selected)") else {
            XCTFail("no label or capsule for \(selected) at \(category.rawValue), \(width) pt")
            continue
          }
          let at = "\(selected) at \(category.rawValue), \(width) pt"
          XCTAssertGreaterThanOrEqual(label.minX - slot.minX, padding, "left, \(at)")
          XCTAssertGreaterThanOrEqual(slot.maxX - label.maxX, padding, "right, \(at)")
          XCTAssertGreaterThanOrEqual(label.minY - slot.minY, padding, "top, \(at): label \(label.minY - slot.minY) pt below the capsule top")
          XCTAssertGreaterThanOrEqual(slot.maxY - label.maxY, padding, "bottom, \(at): label \(slot.maxY - label.maxY) pt above the capsule bottom")
        }
      }
    }
  }

  func testFiveSlotsFitInsideTheBarWithoutClippingOrOverlap() {
    let order = ["slot:Home", "slot:Ledger", "slot:add", "slot:Insights", "slot:Accounts"]
    for width in Self.widths {
      for size in Self.checkedSizes {
        let measured = measure(width: width, category: size.category)
        guard let bar = measured.frame("bar") else {
          XCTFail("no bar frame at \(size.name), \(width) pt")
          continue
        }
        XCTAssertGreaterThan(bar.width, width - 60, "bar not inset as in RootView at \(width) pt")
        var previous: CGRect?
        for name in order {
          guard let slot = measured.frame(name) else {
            XCTFail("no slot frame \(name) at \(size.name), \(width) pt")
            continue
          }
          XCTAssertGreaterThanOrEqual(slot.minX, bar.minX - 0.5, "\(name) clipped on the left at \(size.name), \(width) pt")
          XCTAssertLessThanOrEqual(slot.maxX, bar.maxX + 0.5, "\(name) clipped on the right at \(size.name), \(width) pt")
          if let previous {
            XCTAssertLessThanOrEqual(previous.maxX, slot.minX + 0.5, "\(name) overlaps its neighbour at \(size.name), \(width) pt")
          }
          previous = slot
        }
        for title in Self.tabTitles {
          guard let label = measured.frame("label:\(title)"), let slot = measured.frame("slot:\(title)") else {
            XCTFail("no label or slot for \(title) at \(size.name), \(width) pt")
            continue
          }
          XCTAssertGreaterThanOrEqual(label.minX, slot.minX - 0.5, "\(title) label outside its slot at \(size.name), \(width) pt")
          XCTAssertLessThanOrEqual(label.maxX, slot.maxX + 0.5, "\(title) label outside its slot at \(size.name), \(width) pt")
        }
      }
    }
  }

  /// The cap holds in the real view: above `xxLarge` the labels and the bar measure
  /// exactly as they do at `xxLarge`. Removing the cap makes this fail.
  func testCapHoldsLabelWidthsAndBarAboveTheCap() {
    for width in Self.widths {
      let atCap = measure(width: width, category: Self.capCategory)
      for category in [UIContentSizeCategory.extraExtraLarge, .extraExtraExtraLarge, .accessibilityMedium, .accessibilityExtraExtraExtraLarge] {
        let above = measure(width: width, category: category)
        for title in Self.tabTitles {
          let capWidth = atCap.frame("label:\(title)")?.width ?? -1
          let aboveWidth = above.frame("label:\(title)")?.width ?? -2
          XCTAssertEqual(aboveWidth, capWidth, accuracy: 0.5, "\(title) grows above the cap at \(width) pt, \(category.rawValue)")
        }
        XCTAssertEqual(above.frame("bar")?.height ?? -1, atCap.frame("bar")?.height ?? -2, accuracy: 0.5, "bar grows above the cap at \(width) pt, \(category.rawValue)")
      }
    }
  }

  /// Each selected capsule contains its label with the padding on both sides, for every
  /// tab selected, at 375, 390, 402 and 440 pt, at Large, the cap and AX-XXXL (D10).
  func testSelectedCapsuleContainsItsLabelWithPaddingForEveryTab() {
    let minimumInset = NomiTabBarSizing.capsuleLabelPadding - 0.5
    let checked: [UIContentSizeCategory] = [.large, .extraLarge, .accessibilityExtraExtraExtraLarge]
    for selected in Self.tabTitles {
      for width in Self.widths {
        for category in checked {
          let measured = measure(width: width, category: category, selectedID: selected.lowercased())
          guard let label = measured.frame("label:\(selected)"), let slot = measured.frame("slot:\(selected)") else {
            XCTFail("no label or capsule for \(selected) at \(category.rawValue), \(width) pt")
            continue
          }
          XCTAssertGreaterThanOrEqual(
            label.minX - slot.minX, minimumInset,
            "\(selected) capsule leaves \(label.minX - slot.minX) pt on the left at \(category.rawValue), \(width) pt"
          )
          XCTAssertGreaterThanOrEqual(
            slot.maxX - label.maxX, minimumInset,
            "\(selected) capsule leaves \(slot.maxX - label.maxX) pt on the right at \(category.rawValue), \(width) pt"
          )
        }
      }
    }
  }

  /// The rule in `NomiTabBarSizing` fed with the widths the device drew, at every
  /// size up to the cap. The rule must say they fit at 375 pt.
  func testMeasuredLabelWidthsAgreeWithTheSizingRuleAtNarrowestWidth() {
    let budget = NomiTabBarSizing.tabSpaceBudget(screenWidth: 375, sideMargin: 24)
    for size in Self.tableSizes {
      let measured = measure(width: 440, category: size.category)
      let widths = Self.tabTitles.compactMap { measured.frame("label:\($0)")?.width }
      XCTAssertEqual(widths.count, 4, "missing label widths at \(size.name)")
      if NomiTabBarSizing.effectiveTypeSize(typeSize(size.category)) == typeSize(size.category) {
        XCTAssertTrue(
          NomiTabBarSizing.labelsFitOneLine(labelWidths: widths, budget: budget),
          "rule says labels do not fit at 375 pt, \(size.name), widths \(widths)"
        )
      }
    }
  }

  /// Prints the measured widths and heights at every size. Not an assertion: the
  /// source of the table in `NomiTabBarSizing` and in the PR body.
  func testPrintsMeasuredWidthTable() {
    for size in Self.tableSizes {
      let measured = measure(width: 440, category: size.category)
      let row = Self.tabTitles.map { title -> String in
        let label = measured.frame("label:\(title)")
        return "\(title)=\(String(format: "%.1f", label?.width ?? -1))/h\(String(format: "%.1f", label?.height ?? -1))"
      }.joined(separator: " ")
      let bar = measured.frame("bar")?.height ?? -1
      let capsule = measured.frame("slot:Home")?.height ?? -1
      print("TB1TABLE \(size.name) \(row) capsuleH=\(String(format: "%.1f", capsule)) barH=\(String(format: "%.1f", bar)) oneLineH=\(String(format: "%.2f", oneLineHeight(size.category)))")
    }
  }

  // MARK: - Measuring

  private struct Measured {
    let frames: [NomiTabBarFrame]

    var bar: CGRect {
      frame("bar") ?? .zero
    }

    func frame(_ name: String) -> CGRect? {
      frames.first { $0.name == name }?.frame
    }
  }

  private final class Capture {
    var frames: [NomiTabBarFrame] = []
  }

  /// Hosts the real bar at `width`, inside RootView's margins, with the category set
  /// through UIKit's trait override. Lays it out and returns the published frames.
  private func measure(width: CGFloat, category: UIContentSizeCategory, selectedID: String = "home") -> Measured {
    let capture = Capture()
    let bar = NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "ledger", title: "Ledger", symbolName: "list.bullet.rectangle"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.pie"),
        NomiTabBarItem(id: "accounts", title: "Accounts", symbolName: "creditcard"),
      ],
      selectedID: selectedID,
      onSelect: { _ in },
      onAdd: {}
    )
    // RootView's margins: 24 pt on the sides, 22 pt from the bottom.
    .padding(.horizontal, 24)
    .padding(.bottom, 22)
    .onPreferenceChange(NomiTabBarFramesKey.self) { capture.frames = $0 }

    let controller = UIHostingController(rootView: AnyView(bar))
    controller.traitOverrides.preferredContentSizeCategory = category
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 900))
    window.rootViewController = controller
    window.isHidden = false
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    controller.view.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    window.isHidden = true
    return Measured(frames: capture.frames)
  }

  /// One line of the tab label at `category`, from the scaled font the system uses.
  private func oneLineHeight(_ category: UIContentSizeCategory) -> CGFloat {
    let base = UIFont(name: NomiFont.interMedium, size: 10.5) ?? UIFont.systemFont(ofSize: 10.5)
    let traits = UITraitCollection(preferredContentSizeCategory: category)
    return UIFontMetrics(forTextStyle: .caption2).scaledFont(for: base, compatibleWith: traits).lineHeight
  }

  /// The `DynamicTypeSize` a UIKit category maps to, for `NomiTabBarSizing.effectiveTypeSize`.
  private func typeSize(_ category: UIContentSizeCategory) -> DynamicTypeSize {
    switch category {
    case .extraSmall: return .xSmall
    case .small: return .small
    case .medium: return .medium
    case .large: return .large
    case .extraLarge: return .xLarge
    case .extraExtraLarge: return .xxLarge
    case .extraExtraExtraLarge: return .xxxLarge
    case .accessibilityMedium: return .accessibility1
    case .accessibilityLarge: return .accessibility2
    case .accessibilityExtraLarge: return .accessibility3
    case .accessibilityExtraExtraLarge: return .accessibility4
    case .accessibilityExtraExtraExtraLarge: return .accessibility5
    default: return .large
    }
  }
}
#endif
