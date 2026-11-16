import Foundation
import XCTest

#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

@testable import NomiUI

/// `LicensesLogic` (L1). The split is pure and runs on macOS; the render checks
/// below need a test host and run only on iOS.
final class LicensesLogicTests: XCTestCase {
  private var bundled: String {
    get throws { try XCTUnwrap(AboutLogic.licencesText()) }
  }

  // MARK: - Bound

  func testBundledLicencesSplitIntoSeveralBlocks() throws {
    let blocks = LicensesLogic.blocks(for: try bundled)
    XCTAssertGreaterThan(blocks.count, 10)
  }

  func testNoBundledBlockExceedsTheCharacterBound() throws {
    let blocks = LicensesLogic.blocks(for: try bundled)
    let tallest = blocks.map(\.count).max() ?? 0
    XCTAssertLessThanOrEqual(tallest, LicensesLogic.maxCharactersPerBlock)
  }

  func testSyntheticLinesPackIntoBlocksWithinTheBound() {
    let lines = (1...10).map { "line \($0) " + String(repeating: "x", count: 20) }
    let blocks = LicensesLogic.blocks(for: lines.joined(separator: "\n"), maxCharactersPerBlock: 80)
    XCTAssertGreaterThan(blocks.count, 1)
    XCTAssertTrue(blocks.allSatisfy { $0.count <= 80 })
  }

  // MARK: - Every line, in order, never cut

  func testJoiningTheBlocksGivesBackTheWholeBundledText() throws {
    let text = try bundled
    XCTAssertEqual(LicensesLogic.blocks(for: text).joined(separator: "\n"), text)
  }

  func testEveryBundledLineAppearsOnceAndInOrder() throws {
    let text = try bundled
    let lines = LicensesLogic.blocks(for: text).flatMap { $0.components(separatedBy: "\n") }
    XCTAssertEqual(lines, text.components(separatedBy: "\n"))
  }

  func testSyntheticSplitFallsOnlyBetweenWholeLines() {
    let lines = (1...10).map { "line \($0) " + String(repeating: "x", count: 20) }
    let blocks = LicensesLogic.blocks(for: lines.joined(separator: "\n"), maxCharactersPerBlock: 80)
    XCTAssertEqual(blocks.flatMap { $0.components(separatedBy: "\n") }, lines)
  }

  func testALineLongerThanTheBoundIsKeptWhole() {
    let long = String(repeating: "y", count: 50)
    let blocks = LicensesLogic.blocks(for: "short\n\(long)\nend", maxCharactersPerBlock: 20)
    XCTAssertEqual(blocks, ["short", long, "end"])
  }

  func testShortTextStaysOneBlock() {
    XCTAssertEqual(LicensesLogic.blocks(for: "a\nb"), ["a\nb"])
  }

  func testEmptyTextIsOneEmptyBlock() {
    XCTAssertEqual(LicensesLogic.blocks(for: ""), [""])
  }

  func testLongestBundledLineFitsInsideOneBlock() throws {
    let longest = try bundled.components(separatedBy: "\n").map(\.count).max() ?? 0
    XCTAssertLessThan(longest, LicensesLogic.maxCharactersPerBlock)
  }
}

#if canImport(UIKit)
/// The Licences body draws at every Dynamic Type size the screen supports.
/// Before L1 the single text layer drew nothing at AX3 and AX5. A blank
/// capture here means the body is gone, whatever the layout says.
@MainActor
final class LicensesScreenRenderTests: XCTestCase {
  private func settle() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
  }

  private func host(size: DynamicTypeSize) -> (UIWindow, UIHostingController<AnyView>) {
    let hc = UIHostingController(rootView: AnyView(LicensesScreen().dynamicTypeSize(size)))
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = hc
    window.isHidden = false
    hc.view.frame = window.bounds
    hc.view.layoutIfNeeded()
    settle()
    hc.view.layoutIfNeeded()
    settle()
    return (window, hc)
  }

  private func scrollView(in view: UIView) -> UIScrollView? {
    var found: [UIScrollView] = []
    if let scroll = view as? UIScrollView { found.append(scroll) }
    for sub in view.subviews {
      if let scroll = scrollView(in: sub) { found.append(scroll) }
    }
    return found.max(by: { $0.contentSize.height < $1.contentSize.height })
  }

  /// Pixels in the top `points` rows that differ from the top-left pixel, at 2x.
  private func drawnPixels(in window: UIView, topRows points: CGFloat) -> Int {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
      window.layer.render(in: context.cgContext)
    }
    guard let cg = image.cgImage else { return 0 }
    let width = cg.width
    let rows = min(cg.height, Int(points * 2))
    var data = [UInt8](repeating: 0, count: width * cg.height * 4)
    data.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: cg.height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
      context?.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: cg.height))
    }
    let (r, g, b) = (Int(data[0]), Int(data[1]), Int(data[2]))
    var count = 0
    for row in 0..<rows {
      for column in 0..<width {
        let i = (row * width + column) * 4
        if abs(Int(data[i]) - r) > 16 || abs(Int(data[i + 1]) - g) > 16 || abs(Int(data[i + 2]) - b) > 16 {
          count += 1
        }
      }
    }
    return count
  }

  private func assertBodyDraws(at size: DynamicTypeSize, file: StaticString = #filePath, line: UInt = #line) {
    let (window, hc) = host(size: size)
    defer { window.isHidden = true }
    XCTAssertGreaterThan(drawnPixels(in: window, topRows: 200), 500, "top of body blank", file: file, line: line)
    guard let scroll = scrollView(in: hc.view) else {
      return XCTFail("no scroll view in the Licences screen", file: file, line: line)
    }
    let maxOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
    scroll.setContentOffset(CGPoint(x: 0, y: maxOffset), animated: false)
    scroll.layoutIfNeeded()
    settle()
    XCTAssertGreaterThan(drawnPixels(in: window, topRows: 200), 500, "bottom of body blank", file: file, line: line)
  }

  func testBodyDrawsAtXSmall() {
    assertBodyDraws(at: .xSmall)
  }

  func testBodyDrawsAtLarge() {
    assertBodyDraws(at: .large)
  }

  func testBodyDrawsAtAccessibilitySize3() {
    assertBodyDraws(at: .accessibility3)
  }

  func testBodyDrawsAtAccessibilitySize5() {
    assertBodyDraws(at: .accessibility5)
  }
}
#endif
