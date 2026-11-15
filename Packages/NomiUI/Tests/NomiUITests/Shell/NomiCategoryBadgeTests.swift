import CoreGraphics
import SwiftUI
import XCTest
@testable import NomiUI

final class NomiCategoryBadgeTests: XCTestCase {
  func testNilSlotFallsBackToOther() {
    let badge = NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 40, style: .palette)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.other)
  }

  func testOutOfRangeSlotFallsBackToOther() {
    let badge = NomiCategoryBadge(symbolName: "questionmark", paletteSlot: 99, size: 40, style: .palette)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.other)
  }

  func testValidSlotResolvesToItsPaletteHue() {
    let badge = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 40, style: .palette)
    XCTAssertEqual(badge.resolvedFillForTesting, CategoryPalette.slots[0])
  }

  func testNeutralStyleIgnoresSlot() {
    let slotted = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 32, style: .neutral)
    let unslotted = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: nil, size: 32, style: .neutral)
    XCTAssertEqual(slotted.resolvedFillForTesting, NomiColor.iconTile)
    XCTAssertEqual(unslotted.resolvedFillForTesting, NomiColor.iconTile)
    XCTAssertEqual(slotted.glyphColorForTesting, NomiColor.iconGlyph)
  }

  // MARK: - R2 of the Moss badge: neutral is the default

  func testDefaultStyleIsNeutralMoss() {
    let badge = NomiCategoryBadge(symbolName: "fork.knife", paletteSlot: 0, size: 40)
    XCTAssertEqual(badge.resolvedFillForTesting, NomiColor.iconTile)
    XCTAssertEqual(badge.glyphColorForTesting, NomiColor.iconGlyph)
  }

  // MARK: - Uncategorised uses the warning tones

  func testUncategorisedUsesWarningColours() {
    let badge = NomiCategoryBadge(symbolName: "questionmark", paletteSlot: nil, size: 40, style: .neutral)
    XCTAssertEqual(badge.resolvedFillForTesting, NomiColor.warningTint)
    XCTAssertEqual(badge.glyphColorForTesting, NomiColor.warning)
  }

  // MARK: - D18: the glyph fits a square of 0.45 of the badge

  func testGlyphSideIsFortyFivePercentOfTheBadge() {
    XCTAssertEqual(NomiCategoryBadge.glyphSide(for: 100), 45)
  }

  @MainActor
  func testGlyphFitsSquareForForkKnife() {
    assertGlyphFitsSquare("fork.knife")
  }

  @MainActor
  func testGlyphFitsSquareForBag() {
    assertGlyphFitsSquare("bag")
  }

  /// Renders the badge at 100 pt, one pixel per point, and measures the
  /// glyph's pixels: opaque pixels that differ from the tile fill. A tall
  /// symbol drawn at the old width-only frame overflows the square.
  @MainActor
  private func assertGlyphFitsSquare(_ symbolName: String, file: StaticString = #filePath, line: UInt = #line) {
    let size: CGFloat = 100
    guard let extent = glyphExtent(symbolName: symbolName, size: size) else {
      XCTFail("could not render the badge for \(symbolName)", file: file, line: line)
      return
    }
    let side = NomiCategoryBadge.glyphSide(for: size)
    XCTAssertLessThanOrEqual(extent.height, side + 2, "\(symbolName) glyph is taller than \(side) pt", file: file, line: line)
    XCTAssertLessThanOrEqual(extent.width, side + 2, "\(symbolName) glyph is wider than \(side) pt", file: file, line: line)
  }

  @MainActor
  private func glyphExtent(symbolName: String, size: CGFloat) -> CGSize? {
    let renderer = ImageRenderer(
      content: NomiCategoryBadge(symbolName: symbolName, paletteSlot: nil, size: size, style: .neutral))
    renderer.scale = 1
    guard let image = renderer.cgImage else { return nil }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(
        data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }

    let fill = NomiHex.iconTile
    let fillRed = Int((fill >> 16) & 0xff)
    let fillGreen = Int((fill >> 8) & 0xff)
    let fillBlue = Int(fill & 0xff)
    var minX = width, maxX = -1, minY = height, maxY = -1
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        guard pixels[index + 3] == 255 else { continue }
        let distance = abs(Int(pixels[index]) - fillRed) + abs(Int(pixels[index + 1]) - fillGreen)
          + abs(Int(pixels[index + 2]) - fillBlue)
        guard distance > 60 else { continue }
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    return CGSize(width: maxX - minX + 1, height: maxY - minY + 1)
  }
}
