#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import NomiUI

/// F3a on UIKit: the real icon-only `NomiTabBar` hosted in a `UIHostingController` at
/// phone widths, centred the way RootView places it, with the UIKit content-size
/// category set per case. Every number is read from rendered frames: circle and bar
/// frames come from `NomiTabBarFramesKey` (global coordinates), and the height the
/// screen receives comes from `onHeightChange`.
///
/// This file is iOS-only. `swift test` on macOS compiles it out. Run it with
/// `xcodebuild test -scheme NomiUI -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`.
@MainActor
final class NomiTabBarLayoutTests: XCTestCase {
  private static let widths: [CGFloat] = [375, 390, 402, 440]
  /// From the default size to the largest accessibility size. The bar must not change
  /// across any of them.
  private static let sizes: [(name: String, category: UIContentSizeCategory)] = [
    ("large", .large),
    ("xLarge", .extraLarge),
    ("xxxLarge", .extraExtraExtraLarge),
    ("accessibilityMedium", .accessibilityMedium),
    ("accessibilityXXXLarge", .accessibilityExtraExtraExtraLarge),
  ]
  /// Left to right, as RootView lays them out: two leading tabs, the `+`, two trailing tabs.
  private static let slotNames = ["slot:home", "slot:activity", "slot:add", "slot:insights", "slot:plan"]

  // MARK: - Tests

  func testBarIs308By68AtEveryWidthAndSize() {
    for width in Self.widths {
      for size in Self.sizes {
        let bar = measure(width: width, category: size.category).frame("bar")
        XCTAssertEqual(bar?.width ?? -1, 308, accuracy: 0.5, "bar width at \(size.name), \(width) pt")
        XCTAssertEqual(bar?.height ?? -1, 68, accuracy: 0.5, "bar height at \(size.name), \(width) pt")
      }
    }
  }

  func testBarIsCentredAtEveryWidth() {
    for width in Self.widths {
      let bar = measure(width: width, category: .large).frame("bar")
      XCTAssertEqual(bar?.midX ?? -1, width / 2, accuracy: 0.5, "bar is not centred at \(width) pt")
    }
  }

  func testFiveCirclesAre54PointsWithSixPointGapsAndFitInTheBar() {
    for width in Self.widths {
      for size in Self.sizes {
        let measured = measure(width: width, category: size.category)
        guard let bar = measured.frame("bar") else {
          XCTFail("no bar frame at \(size.name), \(width) pt")
          continue
        }
        var previous: CGRect?
        for name in Self.slotNames {
          guard let slot = measured.frame(name) else {
            XCTFail("no circle frame \(name) at \(size.name), \(width) pt")
            continue
          }
          XCTAssertEqual(slot.width, 54, accuracy: 0.5, "\(name) width at \(size.name), \(width) pt")
          XCTAssertEqual(slot.height, 54, accuracy: 0.5, "\(name) height at \(size.name), \(width) pt")
          XCTAssertGreaterThanOrEqual(slot.minX, bar.minX + 6.5, "\(name) inside the padding, left, \(width) pt")
          XCTAssertLessThanOrEqual(slot.maxX, bar.maxX - 6.5, "\(name) inside the padding, right, \(width) pt")
          if let previous {
            XCTAssertEqual(slot.minX - previous.maxX, 6, accuracy: 0.5, "gap before \(name) at \(size.name), \(width) pt")
          }
          previous = slot
        }
      }
    }
  }

  func testPlusIsTheCentreOfFive() {
    for width in Self.widths {
      let measured = measure(width: width, category: .large)
      let plus = measured.frame("slot:add")
      let bar = measured.frame("bar")
      XCTAssertEqual(plus?.midX ?? -1, bar?.midX ?? -2, accuracy: 0.5, "+ is not the centre circle at \(width) pt")
      let tabsLeftOfPlus = Self.slotNames.prefix(2).compactMap { measured.frame($0) }
      XCTAssertEqual(tabsLeftOfPlus.count, 2, "missing leading tabs at \(width) pt")
      XCTAssertTrue(tabsLeftOfPlus.allSatisfy { $0.maxX <= (plus?.minX ?? -1) }, "a leading tab is not left of + at \(width) pt")
    }
  }

  /// The screen pads its content from the height the bar reports. #169 found the
  /// preference path reads 0 at RootView, so the callback is what F3b relies on.
  func testReportedHeightIs68AtEveryWidth() {
    for width in Self.widths {
      let measured = measure(width: width, category: .large)
      XCTAssertFalse(measured.reportedHeights.isEmpty, "onHeightChange never fired at \(width) pt")
      XCTAssertEqual(measured.reportedHeights.last ?? -1, 68, accuracy: 0.5, "reported height at \(width) pt")
    }
  }

  // MARK: - Measuring

  private struct Measured {
    let frames: [NomiTabBarFrame]
    let reportedHeights: [CGFloat]

    func frame(_ name: String) -> CGRect? {
      frames.first { $0.name == name }?.frame
    }
  }

  private final class Capture {
    var frames: [NomiTabBarFrame] = []
    var heights: [CGFloat] = []
  }

  /// Hosts the real bar at `width` with its frame centred in the window, as RootView
  /// places it, with the category set through UIKit's trait override. Lays it out,
  /// lets the run loop deliver the geometry callbacks, and returns what was published.
  private func measure(width: CGFloat, category: UIContentSizeCategory) -> Measured {
    let capture = Capture()
    let bar = NomiTabBar(
      leading: [
        NomiTabBarItem(id: "home", title: "Home", symbolName: "house"),
        NomiTabBarItem(id: "activity", title: "Activity", symbolName: "text.alignleft"),
      ],
      trailing: [
        NomiTabBarItem(id: "insights", title: "Insights", symbolName: "chart.bar"),
        NomiTabBarItem(id: "plan", title: "Plan", symbolName: "target"),
      ],
      selectedID: "home",
      onSelect: { _ in },
      onAdd: {},
      onHeightChange: { capture.heights.append($0) }
    )
    .frame(maxWidth: .infinity)
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
    return Measured(frames: capture.frames, reportedHeights: capture.heights)
  }
}
#endif
